use core::option::Option;
use starknet::ContractAddress;


// ========================================
// CONTRACT INTERFACE - Betting System
// ========================================

#[starknet::interface]
pub trait IBettingSystem<TContractState> {
    fn get_active_bet_pools(self: @TContractState) -> Array<BetPool>;

    fn create_bet_pool(
        ref self: TContractState,
        tournament_id: u64,
        match_id: u64,
        name: felt252,
        description: ByteArray,
        min_bet: u256,
        max_bet: u256,
        closes_at: u64,
        category: felt252,
        outcomes: Array<felt252>,
    ) -> u64;

    fn get_total_pools(self: @TContractState) -> u64;
    fn get_pool_by_id(self: @TContractState, pool_id: u64) -> BetPool;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn place_bet(ref self: TContractState, pool_id: u64, predicted_outcome: felt252, amount: u256);

    fn get_bet_details(
        self: @TContractState, bettor: ContractAddress, pool_id: u64,
    ) -> Option<BetDetails>;
}

// ========================================
// DATA STRUCTURES
// ========================================

#[derive(Drop, Serde, starknet::Store)]
struct BetPool {
    pub pool_id: u64,
    pub tournament_id: u64,
    pub match_id: u64,
    pub name: felt252,
    pub description: ByteArray,
    pub total_amount: u256,
    pub min_bet: u256,
    pub max_bet: u256,
    pub created_at: u64,
    pub closes_at: u64,
    pub is_open: bool,
    pub creator: ContractAddress,
    pub total_bets: u32,
    pub category: felt252,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct BetDetails {
    pub bettor: ContractAddress,
    pub pool_id: u64,
    pub predicted_outcome: felt252,
    pub amount: u256,
    pub placed_at: u64,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct PoolStatus {
    pub pool_id: u64,
    pub is_active: bool,
    pub last_updated: u64,
}

// ========================================
// MAIN CONTRACT - Betting System
// ========================================

#[starknet::contract]
pub mod BettingSystem {
    use core::num::traits::Zero;
    use core::option::Option;
    use starknet::storage::*;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::{BetDetails, BetPool, IBettingSystem, PoolStatus};

    // Contract storage
    #[storage]
    pub struct Storage {
        // Total pools counter
        total_pools: u64,
        // Pools mapping by ID
        pools: Map<u64, BetPool>,
        // Status mapping by ID
        pool_status: Map<u64, PoolStatus>,
        // Active pools list for efficient querying
        active_pool_ids: Vec<u64>,
        // Stores outcomes for each pool
        outcomes_per_pool: Map<u64, Vec<felt252>>,
        // Owner of the contract (new)
        owner: ContractAddress,
        // bettor_address, pool_id > BetDetails
        bets: Map<(ContractAddress, u64), BetDetails>,
        // Track if a bettor has placed a bet in a specific pool
        has_bet: Map<(ContractAddress, u64), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BetPoolCreated: BetPoolCreated,
        PoolClosed: PoolClosed,
        BetPlaced: BetPlaced,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BetPlaced {
        #[key]
        pub pool_id: u64,
        #[key]
        pub bettor: ContractAddress,
        pub predicted_outcome: felt252,
        pub amount: u256,
        pub placed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BetPoolCreated {
        #[key]
        pub pool_id: u64,
        #[key]
        pub tournament_id: u64,
        pub match_id: u64,
        pub name: felt252,
        pub closes_at: u64,
        #[key]
        pub creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PoolClosed {
        #[key]
        pub pool_id: u64,
        pub closed_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_owner: ContractAddress) {
        assert(!initial_owner.is_zero(), 'INVALID_ADDRESS');
        self.owner.write(initial_owner);
    }


    #[abi(embed_v0)]
    pub impl BettingSystemImpl of IBettingSystem<ContractState> {
        // Create a new bet pool
        fn create_bet_pool(
            ref self: ContractState,
            tournament_id: u64,
            match_id: u64,
            name: felt252,
            description: ByteArray,
            min_bet: u256,
            max_bet: u256,
            closes_at: u64,
            category: felt252,
            outcomes: Array<felt252>,
        ) -> u64 {
            self._assert_only_owner();
            assert(min_bet < max_bet, 'INVALID_BET_LIMITS');
            assert(!outcomes.is_empty(), 'NO_OUTCOMES_PROVIDED');

            let current_timestamp = get_block_timestamp();
            assert(closes_at > current_timestamp, 'POOL_CLOSES_IN_PAST');

            let pool_id = self.total_pools.read() + 1;
            let creator = get_caller_address();

            // Create new BetPool instance
            let new_pool = BetPool {
                pool_id,
                tournament_id,
                match_id,
                name,
                description,
                total_amount: 0,
                min_bet,
                max_bet,
                created_at: current_timestamp,
                closes_at,
                is_open: true,
                creator,
                total_bets: 0,
                category,
            };

            // Store the new pool
            self.pools.write(pool_id, new_pool);

            // Update total pools counter
            self.total_pools.write(pool_id);

            // Add to active pools list
            self.active_pool_ids.push(pool_id);

            // Store outcomes for the pool

            let mut outcomes_vec_entry = self.outcomes_per_pool.entry(pool_id);

            // Iterate over the elements of the memory array 'outcomes'
            let outcomes_len = outcomes.len();
            let mut i = 0;
            loop {
                if i == outcomes_len {
                    break;
                }
                let outcome_element = outcomes.at(i);
                outcomes_vec_entry.push(*outcome_element);
                i += 1;
            }

            // Emit event
            self
                .emit(
                    Event::BetPoolCreated(
                        BetPoolCreated {
                            pool_id, tournament_id, match_id, name, closes_at, creator,
                        },
                    ),
                );

            pool_id
        }

        fn get_active_bet_pools(self: @ContractState) -> Array<BetPool> {
            let mut active_pools = ArrayTrait::new();
            let active_ids_len = self.active_pool_ids.len();

            let mut i = 0;
            loop {
                if i >= active_ids_len {
                    break;
                }

                let pool_id = self.active_pool_ids.at(i).read();
                let pool = self.pools.read(pool_id);
                let status = self.pool_status.read(pool_id);

                // Filter by is_open == true as required
                if pool.is_open && status.is_active {
                    active_pools.append(pool);
                }

                i += 1;
            }

            active_pools
        }

        fn get_total_pools(self: @ContractState) -> u64 {
            self.total_pools.read()
        }

        fn get_pool_by_id(self: @ContractState, pool_id: u64) -> BetPool {
            assert(pool_id > 0, 'INVALID_POOL_ID');

            // Retrieve the pool from storage
            let pool = self.pools.read(pool_id);
            pool
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
        fn place_bet(
            ref self: ContractState, pool_id: u64, predicted_outcome: felt252, amount: u256,
        ) {
            let caller = get_caller_address();
            let current_timestamp = get_block_timestamp();

            // Validate pool exists and is open
            assert(pool_id > 0, 'INVALID_POOL_ID');
            let mut pool = self.pools.read(pool_id);
            assert(pool.pool_id != 0, 'POOL_NOT_EXISTS');
            assert(pool.is_open, 'POOL_NOT_OPEN');
            assert(current_timestamp < pool.closes_at, 'POOL_CLOSED');

            // Validate bet amount
            assert(amount >= pool.min_bet, 'BET_TOO_LOW');
            assert(amount <= pool.max_bet, 'BET_TOO_HIGH');
            assert(amount > 0, 'INVALID_BET_AMOUNT');

            // Prevent multiple bets from same address in same pool
            let bet_key = (caller, pool_id);
            assert(!self.has_bet.read(bet_key), 'ALREADY_PLACED_BET');

            // Validate outcome exists for this pool
            self._validate_outcome_exists(pool_id, predicted_outcome);

            // Create bet details
            let bet_details = BetDetails {
                bettor: caller, pool_id, predicted_outcome, amount, placed_at: current_timestamp,
            };

            // Store the bet
            self.bets.write(bet_key, bet_details);
            self.has_bet.write(bet_key, true);

            // Update pool statistics
            pool.total_amount += amount;
            pool.total_bets += 1;
            self.pools.write(pool_id, pool);

            // Emit event
            self
                .emit(
                    Event::BetPlaced(
                        BetPlaced {
                            pool_id,
                            bettor: caller,
                            predicted_outcome,
                            amount,
                            placed_at: current_timestamp,
                        },
                    ),
                );
        }

        fn get_bet_details(
            self: @ContractState, bettor: ContractAddress, pool_id: u64,
        ) -> Option<BetDetails> {
            let bet_key = (bettor, pool_id);
            if self.has_bet.read(bet_key) {
                Option::Some(self.bets.read(bet_key))
            } else {
                Option::None
            }
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _assert_only_owner(self: @ContractState) {
            let owner = self.owner.read();
            let caller = get_caller_address();
            assert(caller == owner, 'CALLER_NOT_OWNER');
        }
        fn _validate_outcome_exists(self: @ContractState, pool_id: u64, outcome: felt252) {
            let outcomes_vec = self.outcomes_per_pool.entry(pool_id);
            let outcomes_len = outcomes_vec.len();
            let mut found = false;
            let mut i = 0;

            loop {
                if i >= outcomes_len {
                    break;
                }

                let stored_outcome = outcomes_vec.at(i).read();
                if stored_outcome == outcome {
                    found = true;
                    break;
                }

                i += 1;
            }

            assert(found, 'INVALID_OUTCOME');
        }
    }
}
