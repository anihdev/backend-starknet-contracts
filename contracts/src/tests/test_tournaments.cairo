use dojo::test_utils::{deploy_contract, spawn_test_world};
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
use super::super::modules::teams::TeamComponent::Team;
use super::super::modules::tournaments::TournamentComponent::{
    Match, MatchParticipation, PERMISSION_MANAGE_TEAMS, PERMISSION_MANAGE_TOURNAMENT,
    PERMISSION_RECORD_MATCH, Tournament, TournamentOrganizer,
};
use super::super::modules::tournaments::TournamentSystem::{
    ITournamentSystemDispatcher, ITournamentSystemDispatcherTrait,
};

fn setup_world() -> (
    IWorldDispatcher, ITournamentSystemDispatcher, ContractAddress, ContractAddress,
) {
    // Deploy world and contract
    let mut models = array![
        Tournament::TEST_CLASS_HASH,
        TournamentOrganizer::TEST_CLASS_HASH,
        Match::TEST_CLASS_HASH,
        MatchParticipation::TEST_CLASS_HASH,
        Team::TEST_CLASS_HASH,
    ];

    let world = spawn_test_world(models);

    let contract_address = world
        .deploy_contract(
            'salt', TournamentSystem::TEST_CLASS_HASH.try_into().unwrap(), array![].span(),
        );
    let tournament_system = ITournamentSystemDispatcher { contract_address };

    let organizer = contract_address_const::<0x123>();
    let referee = contract_address_const::<0x456>();

    (world, tournament_system, organizer, referee)
}

#[test]
#[available_gas(20000000)]
fn test_record_match_result_success() {
    let (world, tournament_system, organizer, referee) = setup_world();

    // Setup tournament
    let tournament = Tournament {
        tournament_id: 1,
        name: 'Test Tournament',
        organizer,
        start_time: 1000,
        end_time: 2000,
        status: 'active',
        max_teams: 10,
        current_teams: 2,
    };

    // Setup teams
    let team1 = Team {
        team_id: 1,
        name: 'Team Alpha',
        tournament_id: 1,
        captain: contract_address_const::<0x111>(),
        is_active: true,
        wins: 0,
        losses: 0,
        draws: 0,
    };

    let team2 = Team {
        team_id: 2,
        name: 'Team Beta',
        tournament_id: 1,
        captain: contract_address_const::<0x222>(),
        is_active: true,
        wins: 0,
        losses: 0,
        draws: 0,
    };

    // Setup team participation
    let team1_participation = MatchParticipation {
        tournament_id: 1, team_id: 1, is_participating: true, joined_at: 500,
    };

    let team2_participation = MatchParticipation {
        tournament_id: 1, team_id: 2, is_participating: true, joined_at: 600,
    };

    // Setup referee with permissions
    let referee_organizer = TournamentOrganizer {
        tournament_id: 1, organizer: referee, role: 'referee', permissions: PERMISSION_RECORD_MATCH,
    };

    // Setup match
    let match_data = Match {
        match_id: 101,
        tournament_id: 1,
        team1_id: 1,
        team2_id: 2,
        team1_score: 0,
        team2_score: 0,
        status: 'scheduled',
        scheduled_time: 1500,
        completed_time: 0,
        recorded_by: contract_address_const::<0>(),
    };

    // Set all data in world
    set!(
        world,
        (
            tournament,
            team1,
            team2,
            team1_participation,
            team2_participation,
            referee_organizer,
            match_data,
        ),
    );

    // Test recording match result as referee
    starknet::testing::set_caller_address(referee);
    tournament_system.record_match_result(world, 101, 1, 1, 2, 3, 1);

    // Verify match was updated
    let updated_match: Match = get!(world, 101, Match);
    assert(updated_match.team1_score == 3, 'Team1 score incorrect');
    assert(updated_match.team2_score == 1, 'Team2 score incorrect');
    assert(updated_match.status == 'completed', 'Match status incorrect');
    assert(updated_match.recorded_by == referee, 'Recorded by incorrect');

    // Verify team records updated
    let updated_team1: Team = get!(world, 1, Team);
    let updated_team2: Team = get!(world, 2, Team);
    assert(updated_team1.wins == 1, 'Team1 wins incorrect');
    assert(updated_team1.losses == 0, 'Team1 losses incorrect');
    assert(updated_team2.wins == 0, 'Team2 wins incorrect');
    assert(updated_team2.losses == 1, 'Team2 losses incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_record_match_result_draw() {
    let (world, tournament_system, organizer, referee) = setup_world();

    // Setup similar to success test but with different data
    let tournament = Tournament {
        tournament_id: 1,
        name: 'Test Tournament',
        organizer,
        start_time: 1000,
        end_time: 2000,
        status: 'active',
        max_teams: 10,
        current_teams: 2,
    };

    let team1 = Team {
        team_id: 1,
        name: 'Team Alpha',
        tournament_id: 1,
        captain: contract_address_const::<0x111>(),
        is_active: true,
        wins: 0,
        losses: 0,
        draws: 0,
    };

    let team2 = Team {
        team_id: 2,
        name: 'Team Beta',
        tournament_id: 1,
        captain: contract_address_const::<0x222>(),
        is_active: true,
        wins: 0,
        losses: 0,
        draws: 0,
    };

    let team1_participation = MatchParticipation {
        tournament_id: 1, team_id: 1, is_participating: true, joined_at: 500,
    };

    let team2_participation = MatchParticipation {
        tournament_id: 1, team_id: 2, is_participating: true, joined_at: 600,
    };

    let match_data = Match {
        match_id: 102,
        tournament_id: 1,
        team1_id: 1,
        team2_id: 2,
        team1_score: 0,
        team2_score: 0,
        status: 'scheduled',
        scheduled_time: 1500,
        completed_time: 0,
        recorded_by: contract_address_const::<0>(),
    };

    set!(world, (tournament, team1, team2, team1_participation, team2_participation, match_data));

    // Test recording draw as main organizer
    starknet::testing::set_caller_address(organizer);
    tournament_system.record_match_result(world, 102, 1, 1, 2, 2, 2);

    // Verify draw was recorded correctly
    let updated_team1: Team = get!(world, 1, Team);
    let updated_team2: Team = get!(world, 2, Team);
    assert(updated_team1.draws == 1, 'Team1 draws incorrect');
    assert(updated_team2.draws == 1, 'Team2 draws incorrect');
    assert(updated_team1.wins == 0, 'Team1 wins should be 0');
    assert(updated_team2.wins == 0, 'Team2 wins should be 0');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Unauthorized caller',))]
fn test_record_match_result_unauthorized() {
    let (world, tournament_system, organizer, _referee) = setup_world();

    let tournament = Tournament {
        tournament_id: 1,
        name: 'Test Tournament',
        organizer,
        start_time: 1000,
        end_time: 2000,
        status: 'active',
        max_teams: 10,
        current_teams: 2,
    };

    let match_data = Match {
        match_id: 103,
        tournament_id: 1,
        team1_id: 1,
        team2_id: 2,
        team1_score: 0,
        team2_score: 0,
        status: 'scheduled',
        scheduled_time: 1500,
        completed_time: 0,
        recorded_by: contract_address_const::<0>(),
    };

    set!(world, (tournament, match_data));

    // Try to record as unauthorized user
    let unauthorized_user = contract_address_const::<0x999>();
    starknet::testing::set_caller_address(unauthorized_user);
    tournament_system.record_match_result(world, 103, 1, 1, 2, 3, 1);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Team not in tournament',))]
fn test_record_match_result_team_not_in_tournament() {
    let (world, tournament_system, organizer, _referee) = setup_world();

    let tournament = Tournament {
        tournament_id: 1,
        name: 'Test Tournament',
        organizer,
        start_time: 1000,
        end_time: 2000,
        status: 'active',
        max_teams: 10,
        current_teams: 2,
    };

    // Setup team1 participation but not team2
    let team1_participation = MatchParticipation {
        tournament_id: 1, team_id: 1, is_participating: true, joined_at: 500,
    };

    let team2_participation = MatchParticipation {
        tournament_id: 1, team_id: 2, is_participating: false, // Not participating
        joined_at: 0,
    };

    let match_data = Match {
        match_id: 104,
        tournament_id: 1,
        team1_id: 1,
        team2_id: 2,
        team1_score: 0,
        team2_score: 0,
        status: 'scheduled',
        scheduled_time: 1500,
        completed_time: 0,
        recorded_by: contract_address_const::<0>(),
    };

    set!(world, (tournament, team1_participation, team2_participation, match_data));

    starknet::testing::set_caller_address(organizer);
    tournament_system.record_match_result(world, 104, 1, 1, 2, 3, 1);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Match already completed',))]
fn test_record_match_result_already_completed() {
    let (world, tournament_system, organizer, _referee) = setup_world();

    let tournament = Tournament {
        tournament_id: 1,
        name: 'Test Tournament',
        organizer,
        start_time: 1000,
        end_time: 2000,
        status: 'active',
        max_teams: 10,
        current_teams: 2,
    };

    let team1_participation = MatchParticipation {
        tournament_id: 1, team_id: 1, is_participating: true, joined_at: 500,
    };

    let team2_participation = MatchParticipation {
        tournament_id: 1, team_id: 2, is_participating: true, joined_at: 600,
    };

    // Match already completed
    let match_data = Match {
        match_id: 105,
        tournament_id: 1,
        team1_id: 1,
        team2_id: 2,
        team1_score: 2,
        team2_score: 1,
        status: 'completed', // Already completed
        scheduled_time: 1500,
        completed_time: 1800,
        recorded_by: organizer,
    };

    set!(world, (tournament, team1_participation, team2_participation, match_data));

    starknet::testing::set_caller_address(organizer);
    tournament_system.record_match_result(world, 105, 1, 1, 2, 3, 1);
}
