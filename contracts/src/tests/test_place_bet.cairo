use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use crate::modules::betting::BettingSystem::BettingSystem::BetPlaced;
use crate::modules::betting::BettingSystem::{
    BettingSystem, IBettingSystemDispatcher, IBettingSystemDispatcherTrait,
};

fn deploy_contract() -> IBettingSystemDispatcher {
    let contract = declare("BettingSystem").unwrap();
    let owner_address: ContractAddress = contract_address_const::<'owner'>();
    let args = array![owner_address.into()];
    let (contract_address, _err) = contract.contract_class().deploy(@args).unwrap();
    IBettingSystemDispatcher { contract_address }
}

fn setup_pool() -> (IBettingSystemDispatcher, u64) {
    let dispatcher = deploy_contract();

    // Setup owner as caller
    let owner_address = contract_address_const::<'owner'>();
    start_cheat_caller_address(dispatcher.contract_address, owner_address);

    let current_timestamp = 1000_u64;
    start_cheat_block_timestamp(dispatcher.contract_address, current_timestamp);

    // Create a pool
    let mut outcomes = array![];
    outcomes.append('TeamA_Wins');
    outcomes.append('Draw');
    outcomes.append('TeamB_Wins');

    let pool_id = dispatcher.create_bet_pool(
        1_u64,           // tournament_id
        101_u64,         // match_id
        'TestMatch',     // name
        "Test Match",    // description
        10,              // min_bet
        200,             // max_bet
        current_timestamp + 100_u64, // closes_at
        'Sports',        // category
        outcomes,        // outcomes
    );

    (dispatcher, pool_id)
}

#[test]
fn test_place_bet_success() {
    let (dispatcher, pool_id) = setup_pool();
    let mut spy = spy_events();

    // Switch to a bettor
    let bettor_address = contract_address_const::<'bettor1'>();
    start_cheat_caller_address(dispatcher.contract_address, bettor_address);

    let bet_amount = 50_u256;
    let predicted_outcome = 'TeamA_Wins';
    let current_timestamp = 1050_u64;
    start_cheat_block_timestamp(dispatcher.contract_address, current_timestamp);

    // Place bet
    dispatcher.place_bet(pool_id, predicted_outcome, bet_amount);

    // Verify bet was stored
    let bet_details_opt = dispatcher.get_bet_details(bettor_address, pool_id);
    assert(bet_details_opt.is_some(), 'Bet should exist');
    
    let bet_details = bet_details_opt.unwrap();
    assert(bet_details.bettor == bettor_address, 'Wrong bettor');
    assert(bet_details.pool_id == pool_id, 'Wrong pool_id');
    assert(bet_details.predicted_outcome == predicted_outcome, 'Wrong outcome');
    assert(bet_details.amount == bet_amount, 'Wrong amount');

    // Verify event emission
    let expected_event = BettingSystem::Event::BetPlaced(
        BetPlaced {
            pool_id,
            bettor: bettor_address,
            predicted_outcome,
            amount: bet_amount,
            placed_at: current_timestamp,
        }
    );
    spy.assert_emitted(@array![(dispatcher.contract_address, expected_event)]);

    // Verify pool statistics updated
    let pool = dispatcher.get_pool_by_id(pool_id);
    assert(pool.total_amount == bet_amount, 'Pool total should update');
    assert(pool.total_bets == 1, 'Total bets should be 1');
}

#[test]
#[should_panic(expected: 'ALREADY_PLACED_BET')]
fn test_place_bet_duplicate() {
    let (dispatcher, pool_id) = setup_pool();
    
    let bettor_address = contract_address_const::<'bettor1'>();
    start_cheat_caller_address(dispatcher.contract_address, bettor_address);
    start_cheat_block_timestamp(dispatcher.contract_address, 1050_u64);

    // Place first bet
    dispatcher.place_bet(pool_id, 'TeamA_Wins', 50_u256);
    
    // Try to place second bet
    dispatcher.place_bet(pool_id, 'TeamB_Wins', 30_u256);
}

#[test]
#[should_panic(expected: 'BET_TOO_LOW')]
fn test_place_bet_too_low() {
    let (dispatcher, pool_id) = setup_pool();
    
    let bettor_address = contract_address_const::<'bettor1'>();
    start_cheat_caller_address(dispatcher.contract_address, bettor_address);
    start_cheat_block_timestamp(dispatcher.contract_address, 1050_u64);

    // Try to place bet below minimum (min_bet is 10)
    dispatcher.place_bet(pool_id, 'TeamA_Wins', 5_u256);
}

#[test]
#[should_panic(expected: 'BET_TOO_HIGH')]
fn test_place_bet_too_high() {
    let (dispatcher, pool_id) = setup_pool();
    
    let bettor_address = contract_address_const::<'bettor1'>();
    start_cheat_caller_address(dispatcher.contract_address, bettor_address);
    start_cheat_block_timestamp(dispatcher.contract_address, 1050_u64);

    // Try to place bet above maximum (max_bet is 200)
    dispatcher.place_bet(pool_id, 'TeamA_Wins', 250_u256);
}

#[test]
#[should_panic(expected: 'POOL_CLOSED')]
fn test_place_bet_pool_closed() {
    let (dispatcher, pool_id) = setup_pool();
    
    let bettor_address = contract_address_const::<'bettor1'>();
    start_cheat_caller_address(dispatcher.contract_address, bettor_address);
    
    // Set timestamp after pool closes
    start_cheat_block_timestamp(dispatcher.contract_address, 1200_u64);

    dispatcher.place_bet(pool_id, 'TeamA_Wins', 50_u256);
}

#[test]
#[should_panic(expected: 'INVALID_OUTCOME')]
fn test_place_bet_invalid_outcome() {
    let (dispatcher, pool_id) = setup_pool();
    
    let bettor_address = contract_address_const::<'bettor1'>();
    start_cheat_caller_address(dispatcher.contract_address, bettor_address);
    start_cheat_block_timestamp(dispatcher.contract_address, 1050_u64);

    // Try to bet on outcome that doesn't exist
    dispatcher.place_bet(pool_id, 'InvalidOutcome', 50_u256);
}