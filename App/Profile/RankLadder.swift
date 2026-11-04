import HeistCore

/// Rank titles from a rating. A placeholder ladder (4 Nov 2026): the master plan names only the ends,
/// Pickpocket to Master Thief and Cadet to Commissioner; the world bible (task 0.7) names the rest, and
/// renaming happens here only.
enum RankLadder {
    static let thief = ["Pickpocket", "Burglar", "Cat Burglar", "Safecracker", "Mastermind", "Master Thief"]
    static let police = ["Cadet", "Patrol Officer", "Detective", "Inspector", "Chief", "Commissioner"]

    /// Each title spans 150 points in three divisions of 50 (III, then II, then I). New players start at
    /// 1000, Pickpocket II; the lowest title also covers everything below, the highest everything above.
    static let floor = 950
    static let titleSpan = 150
    static let divisions = ["III", "II", "I"]

    static func rank(for rating: Int, role: Role) -> PlayerSummary.Rank {
        let titles = role == .thief ? thief : police
        let above = rating - floor
        let tier = min(max(above >= 0 ? above / titleSpan : 0, 0), titles.count - 1)
        let within = above - tier * titleSpan
        let division = min(max(within >= 0 ? within / (titleSpan / divisions.count) : 0, 0), divisions.count - 1)
        return PlayerSummary.Rank(rating: rating, title: titles[tier], division: divisions[division])
    }
}
