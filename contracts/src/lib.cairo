pub mod modules {
    pub mod tournaments {
        pub mod TournamentSystem;
    }

    pub mod betting {
        pub mod BettingSystem;
    }
}

#[cfg(test)]
mod tests {
    mod test_betting;
    mod test_place_bet;
}
