import CoreGraphics

/// Spacing / radius scale — mirrors `--space-*` steps used across the doc.
enum NTSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
}

/// NOTE: as of this pass `card`/`sheet` still have zero call sites — every
/// screen hard-codes its own `cornerRadius:` literal instead of reading
/// these (26/22/18/16/24/28/20/30 all show up as ad-hoc values across the
/// app). Changing the numbers here is a real, deliberate step toward the
/// tighter "terminal" shape language, but it stays inert until each of
/// those literals is swept over to read `NTRadius.card`/`.sheet` — that
/// sweep is the next, screen-touching phase of this redesign, not done yet.
enum NTRadius {
    static let card: CGFloat = 12
    static let sheet: CGFloat = 18
    static let pill: CGFloat = 999
}
