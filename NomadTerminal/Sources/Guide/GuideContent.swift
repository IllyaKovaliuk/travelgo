import SwiftUI

/// Real field-guide content — practical, standard wilderness-safety
/// guidance organized by situation, not lorem ipsum. Static for now (no
/// backend), same as the design doc's other reference content; a
/// CMS-backed version so this can be corrected/extended without a build is
/// natural future work once there's a reason to edit it outside Xcode.
struct GuideCategory: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let tint: Color
    let situations: [GuideSituation]
}

struct GuideSituation: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let body: LocalizedStringKey
}

extension GuideCategory {
    static let all: [GuideCategory] = [
        GuideCategory(icon: "location.slash.fill", title: "Lost / no signal", tint: NTColor.sage, situations: [
            .init(title: "You've lost the trail", body: "Stop moving. Retrace your last confirmed point using your recorded track if you have one — don't guess a shortcut. Mark your current position, note the time, and give yourself a hard turnaround point before dark or before water runs low. A downloaded route keeps working with zero signal."),
            .init(title: "Phone has no signal at all", body: "Don't waste battery searching for bars while walking. Switch to airplane mode with GPS still on to save power — GPS doesn't need cell signal to work — and only recheck for signal from high, open ground."),
            .init(title: "You're overdue and someone should be worried", body: "This is why you tell someone your plan before you go: route, expected return time, and what to do if you don't check in. The app doesn't call for help on its own — a downloaded route and a real person who knows your plan does that.")
        ]),
        GuideCategory(icon: "car.side", title: "Vehicle stuck or broken down", tint: NTColor.accent, situations: [
            .init(title: "Bogged in mud or sand", body: "Stop spinning the wheels immediately — it digs you in deeper and can overheat the transmission. Clear material from in front of the tires, drop tire pressure for more contact area (10–15 psi on sand, reinflate once out), and use traction boards or brush under the drive wheels if you have them."),
            .init(title: "Vehicle won't start in the backcountry", body: "Don't drain the battery cranking repeatedly. Check the basics first: fuel, obvious loose connections, warning lights. If it's electrical and unfixable roadside, you're generally safer staying with the vehicle than walking out unless you know exactly how far help is."),
            .init(title: "River crossing looks driveable", body: "If you can't see the bottom or the water's above the wheel hubs, walk it first on foot with a rope if it's safe to do so. Fast, murky water hides depth and current — most vehicle water crossings that go wrong were misjudged from the driver's seat, not from actually checking.")
        ]),
        GuideCategory(icon: "figure.walk.motion", title: "Crossing water", tint: NTColor.water, situations: [
            .init(title: "Ford looks higher than expected", body: "Higher, faster, or murkier than when the route was logged means conditions changed — rain upstream can raise a river in hours even under a clear sky where you're standing. Don't cross if you can't see the bottom or the water's above your knees with any real current."),
            .init(title: "Crossing on foot", body: "Unbuckle your pack's hip belt and sternum strap so you can shed it fast if you go down. Face upstream at a slight angle, move sideways, one foot planted before moving the other, and use a pole or stick for a third point of contact."),
            .init(title: "Water's rising while you're on the far side", body: "Cross now or commit to waiting it out — don't split the difference. If the crossing was fine on the way in and looks worse now, assume it'll keep rising.")
        ]),
        GuideCategory(icon: "cloud.bolt.rain.fill", title: "When weather turns", tint: NTColor.gold, situations: [
            .init(title: "Lightning and you're exposed", body: "Get off ridgelines, summits, and open ground immediately. Avoid being the tallest thing around or standing under the tallest thing around — isolated trees are a real hazard. Crouch on your pack, feet together, if there's no better option."),
            .init(title: "Flash-flood terrain (canyons, dry washes)", body: "Rain doesn't have to be falling on you to flood a canyon — storms miles upstream can send a wall of water through a dry wash with almost no warning. If you're in a slot canyon or wash and weather's unsettled anywhere upstream, get to higher ground before you commit."),
            .init(title: "Whiteout or fog on a ridge", body: "Stop before you're disoriented, not after. If you have a downloaded track, trust the compass bearing over your instinct — in zero visibility, people reliably walk in circles without realizing it.")
        ]),
        GuideCategory(icon: "heart.text.square.fill", title: "Altitude & the body", tint: NTColor.extreme, situations: [
            .init(title: "Headache and nausea above 2500–3000m", body: "These are the first signs of altitude sickness, not just fatigue. The only real treatment is descending — pushing on \"to acclimatize\" is how mild AMS becomes dangerous. If symptoms include confusion, stumbling, or won't clear with rest, descend immediately."),
            .init(title: "Someone's not making sense or can't walk straight", body: "Loss of coordination at altitude is a medical emergency, not a \"let's slow down\" situation. Descend now — don't wait for it to pass."),
            .init(title: "Heat exhaustion vs. heatstroke", body: "Heavy sweating, weakness, and nausea is heat exhaustion — stop, shade, water, electrolytes. Confusion, hot dry skin, or collapse is heatstroke — a real emergency; cool the body by any means available and get help moving.")
        ]),
        GuideCategory(icon: "pawprint.fill", title: "Wildlife", tint: NTColor.accentDeep, situations: [
            .init(title: "Large animal at a distance", body: "Don't run — it can trigger a chase response. Back away slowly while facing it, make yourself look bigger, and give it a clear escape route; don't corner it."),
            .init(title: "Snake encountered on the trail", body: "Most bites happen when people try to move or kill the snake. Stop, back away the way you came, and give it space and time to leave on its own."),
            .init(title: "Wildlife has found your camp or food", body: "Prevention beats reaction: food and anything scented goes sealed and away from your sleeping area, ideally hung or in a proper container, every single night, not just when you remember.")
        ]),
        GuideCategory(icon: "doc.text.fill", title: "Permits & border zones", tint: NTColor.sage, situations: [
            .init(title: "Route crosses a border or restricted zone", body: "Check requirements before you go, not at the checkpoint — border-zone permits in places like Svaneti often need days of lead time. Requirements logged on a route are what previous travelers needed; rules change, so confirm locally before you rely on them."),
            .init(title: "No cell signal to verify anything", body: "This is exactly why permits get sorted before departure, not en route. Download a route's requirements before you lose signal so you have them even offline.")
        ]),
        GuideCategory(icon: "cross.case.fill", title: "When it's serious", tint: NTColor.hard, situations: [
            .init(title: "Real injury, can't self-rescue", body: "Stop, assess, treat what you can (bleeding control, keep warm, keep still if a fracture's possible). If you have signal, call local emergency services directly — that's faster and more reliable than anything in this app. Use the app's SOS screen to text your own emergency contacts your position as a backup, not a replacement."),
            .init(title: "Using the in-app SOS screen", body: "Be clear on what it actually is: it opens a pre-filled text message to your own emergency contacts with your last position — nothing more. It's not a satellite beacon, nobody is monitoring it, and nothing is dispatched automatically. It only works at all if you have phone signal and someone added as a contact actually sees the message and chooses to act. For real backcountry trips beyond cell coverage, carry a dedicated device (e.g. a Garmin inReach or similar satellite messenger) — don't rely on this screen for that."),
            .init(title: "A basic kit worth actually carrying", body: "A small first aid kit you know how to use beats a large one you don't. At minimum: bleeding control, blister care, any personal medication, and a real way to call or signal for help where you're going — a phone alone isn't that everywhere.")
        ])
    ]
}
