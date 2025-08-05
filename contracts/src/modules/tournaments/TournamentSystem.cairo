// use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
// use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
// use super::TournamentEvents::MatchResultRecorded;
// use super::super::teams::TeamComponent::Team;
// use super::{Match, MatchParticipation, Tournament, TournamentOrganizer, Organizer};

// // Errors
// const UNAUTHORIZED_CALLER: felt252 = 'Unauthorized caller';
// const INVALID_TOURNAMENT: felt252 = 'Invalid tournament';
// const INVALID_MATCH: felt252 = 'Invalid match';
// const TEAM_NOT_IN_TOURNAMENT: felt252 = 'Team not in tournament';
// const MATCH_ALREADY_COMPLETED: felt252 = 'Match already completed';

// #[dojo::interface]
// trait ITournamentSystem {
//     fn record_match_result(
//         ref world: IWorldDispatcher,
//         match_id: u32,
//         tournament_id: u32,
//         team1_id: u32,
//         team2_id: u32,
//         team1_score: u32,
//         team2_score: u32,
//     );

//     fn create_match(
//         ref world: IWorldDispatcher,
//         tournament_id: u32,
//         team1_id: u32,
//         team2_id: u32,
//         scheduled_time: u64,
//     ) -> u32;

//     fn add_tournament_organizer(
//         ref world: IWorldDispatcher,
//         tournament_id: u32,
//         organizer: ContractAddress,
//         role: felt252,
//         permissions: u32,
//     );

//     fn get_tournaments_by_creator(
//         ref world: IWorldDispatcher, creator: ContractAddress,
//     ) -> Array<u32>; // returning Array<u32> (Vec equivalent)
// }

// #[dojo::contract]
// mod tournament_system {
//     use super::*;

//     #[abi(embed_v0)]
//     impl TournamentSystemImpl of super::ITournamentSystem<ContractState> {
//         fn record_match_result(
//             ref world: IWorldDispatcher,
//             match_id: u32,
//             tournament_id: u32,
//             team1_id: u32,
//             team2_id: u32,
//             team1_score: u32,
//             team2_score: u32,
//         ) {
//             let caller = get_caller_address();
//             let current_time = get_block_timestamp();

//             // Validate tournament exists and is active
//             let tournament: Tournament = get!(world, tournament_id, Tournament);
//             assert(tournament.tournament_id == tournament_id, INVALID_TOURNAMENT);
//             assert(tournament.status == 'active', INVALID_TOURNAMENT);

//             // Check authorization - caller must be organizer or referee with proper permissions
//             let organizer: TournamentOrganizer = get!(
//                 world, (tournament_id, caller), TournamentOrganizer,
//             );
//             let has_permission = organizer.permissions & super::PERMISSION_RECORD_MATCH != 0;
//             assert(has_permission || tournament.organizer == caller, UNAUTHORIZED_CALLER);

//             // Validate teams exist in tournament
//             let team1_participation: MatchParticipation = get!(
//                 world, (tournament_id, team1_id), MatchParticipation,
//             );
//             let team2_participation: MatchParticipation = get!(
//                 world, (tournament_id, team2_id), MatchParticipation,
//             );
//             assert(team1_participation.is_participating, TEAM_NOT_IN_TOURNAMENT);
//             assert(team2_participation.is_participating, TEAM_NOT_IN_TOURNAMENT);

//             // Get and validate match
//             let mut match_data: Match = get!(world, match_id, Match);
//             assert(match_data.match_id == match_id, INVALID_MATCH);
//             assert(match_data.tournament_id == tournament_id, INVALID_MATCH);
//             assert(
//                 match_data.team1_id == team1_id && match_data.team2_id == team2_id,
//                 INVALID_MATCH,
//             );
//             assert(match_data.status != 'completed', MATCH_ALREADY_COMPLETED);

//             // Update match with results
//             match_data.team1_score = team1_score;
//             match_data.team2_score = team2_score;
//             match_data.status = 'completed';
//             match_data.completed_time = current_time;
//             match_data.recorded_by = caller;

//             // Update team records
//             let mut team1: Team = get!(world, team1_id, Team);
//             let mut team2: Team = get!(world, team2_id, Team);

//             if team1_score > team2_score {
//                 team1.wins += 1;
//                 team2.losses += 1;
//             } else if team2_score > team1_score {
//                 team2.wins += 1;
//                 team1.losses += 1;
//             } else {
//                 team1.draws += 1;
//                 team2.draws += 1;
//             }

//             // Save updated data
//             set!(world, (match_data));
//             set!(world, (team1, team2));

//             // Emit event
//             emit!(
//                 world,
//                 MatchResultRecorded {
//                     match_id,
//                     tournament_id,
//                     team1_id,
//                     team2_id,
//                     team1_score,
//                     team2_score,
//                     recorded_by: caller,
//                     recorded_at: current_time,
//                 },
//             );
//         }

//         fn create_match(
//             ref world: IWorldDispatcher,
//             tournament_id: u32,
//             team1_id: u32,
//             team2_id: u32,
//             scheduled_time: u64,
//         ) -> u32 {
//             let caller = get_caller_address();

//             // Validate tournament and authorization
//             let tournament: Tournament = get!(world, tournament_id, Tournament);
//             assert(tournament.tournament_id == tournament_id, INVALID_TOURNAMENT);

//             let organizer: TournamentOrganizer = get!(
//                 world, (tournament_id, caller), TournamentOrganizer,
//             );
//             let has_permission = organizer.permissions & super::PERMISSION_MANAGE_TOURNAMENT !=
//             0;
//             assert(has_permission || tournament.organizer == caller, UNAUTHORIZED_CALLER);

//             // Generate match ID (simple counter - in production use better ID generation)
//             let match_id = tournament_id * 10000 + team1_id * 100 + team2_id;

//             let new_match = Match {
//                 match_id,
//                 tournament_id,
//                 team1_id,
//                 team2_id,
//                 team1_score: 0,
//                 team2_score: 0,
//                 status: 'scheduled',
//                 scheduled_time,
//                 completed_time: 0,
//                 recorded_by: starknet::contract_address_const::<0>(),
//             };

//             set!(world, (new_match));
//             match_id
//         }

//         fn add_tournament_organizer(
//             ref world: IWorldDispatcher,
//             tournament_id: u32,
//             organizer: ContractAddress,
//             role: felt252,
//             permissions: u32,
//         ) {
//             let caller = get_caller_address();

//             // Only main organizer can add other organizers
//             let tournament: Tournament = get!(world, tournament_id, Tournament);
//             assert(tournament.organizer == caller, UNAUTHORIZED_CALLER);

//             let new_organizer = TournamentOrganizer { tournament_id, organizer, role, permissions
//             };

//             set!(world, (new_organizer));
//         }

//         fn get_tournaments_by_creator(
//             ref world: IWorldDispatcher, creator: ContractAddress,
//         ) -> Array<u32> {
//             let org: Organizer = get!(world, creator, Organizer);
//             org.tournament_ids
//         }
//     }
// }
