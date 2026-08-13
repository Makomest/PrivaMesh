//
//  OrbitChatsView.swift
//  privamesh
//
//  "Orbit" chat surface — one live scene that morphs between a 3D contact
//  sphere, a vertical timeline, and a search focus. Drawn with a single Canvas
//  (manual 3D projection + spring physics), so the sphere nodes and the timeline
//  rows are literally the same objects flying between layouts.
//
//  Strictly monochrome. With no colour to lean on, hierarchy is Apple's: size,
//  weight, and label opacity. Unread is the only white FILL in the scene; active
//  now is a white STROKE; depth is opacity + scale.
//
//  Self-contained: this uses its own greyscale palette and does NOT touch
//  Theme — the rest of the app keeps its teal "Liquid Glass" identity.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Orbit palette (single dark world — light emerging from graphite)

// Greyscale only — no hue anywhere. Hierarchy is carried the way Apple carries
// it: weight, size, and label opacity. Attention is a white FILL (unread count);
// state is a white STROKE (active now) — the two read apart without any colour.
enum Orbit {
    static let bg0   = Color.black                       // true black (OLED)
    static let bg1   = Color(white: 0.055)               // faint lift behind the scene
    static let label = Color.white                       // primary
    static let label2 = Color(white: 1.0, opacity: 0.55) // secondary (Apple secondaryLabel)
    static let label3 = Color(white: 1.0, opacity: 0.30) // tertiary
    static let ink   = Color.black                       // numerals inside a white fill

    /// Avatar discs. Four neutral steps only — enough to tell contacts apart at
    /// a glance, never enough to read as colour.
    static let tones: [Color] = [
        Color(white: 0.22), Color(white: 0.30), Color(white: 0.26), Color(white: 0.34),
    ]
}

// MARK: - Glass

/// Frosted panel: material + a hairline border that catches light at the top-left
/// and falls away to nothing at the bottom-right — the edge is what makes a pane
/// read as glass rather than as a grey box. Greyscale only.
///
/// Applied ONLY to layers that float above the scene (search, quick reply, hints).
/// Frosting every surface at once is exactly what the direction rules out.
private struct OrbitGlass: ViewModifier {
    var cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                // No material — a translucent pane like the chat bubbles. The
                // scene shows straight through it; the edge does the glass work.
                shape.fill(Color.white.opacity(0.06))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.10), Color.white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
    }
}
private extension View {
    func orbitGlass(_ cornerRadius: CGFloat) -> some View {
        modifier(OrbitGlass(cornerRadius: cornerRadius))
    }
}

private func easeInOut(_ t: Double) -> Double {
    t < 0.5 ? 4*t*t*t : 1 - pow(-2*t + 2, 3)/2
}
private func clampd(_ v: Double, _ a: Double, _ b: Double) -> Double { min(max(v, a), b) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

// MARK: - Node

struct OrbitNode {
    let contactID: String
    let name: String
    let initials: String
    let tone: Color
    var unread: Int
    /// How recently they wrote, 1 → just now, 0 → a day or more. The timeline
    /// carries this in its ordering (and its "12 мин" column); the globe has no
    /// order to spend, so it spends the ring's SWEEP instead — a geometric
    /// channel, free of depth, which owns every opacity in the scene.
    var freshness: Double
    var lastText: String
    /// Your private note about them — shown to the right of the name in the list.
    var note: String = ""
    var lastTime: Date
    /// The last message came from them, not from you — an arrival worth turning
    /// the globe for.
    var lastIncoming: Bool
    /// How much you two have talked *lately* (0…1). Drives front-pole gravity
    /// and the ring's weight. Deliberately a recent window, not lifetime volume:
    /// a chat you hammered a year ago is not someone you talk to.
    var freq: Double
    /// Pinned by hand — wears the ring regardless of what the algorithm thinks.
    var isFavourite: Bool
    var row: Int            // timeline order (0 = top)
    /// The globe only holds the most recently active contacts. Older ones stay
    /// list-only: they still occupy a row, they just never appear on the sphere.
    /// Without a cap the sphere keeps packing nodes into the same fixed area
    /// until they overlap and nothing is aimable.
    var onSphere = true

    // sphere position (unit sphere)
    var sx = 0.0, sy = 0.0, sz = 0.0
    // per-frame computed screen state (shared by draw + hit-test)
    var px = 0.0, py = 0.0, size = 8.0, depth = 0.5, fade = 0.0, rowAlpha = 0.0
    /// Filtered out by the chat-list search — forced off-screen and invisible,
    /// so it neither renders nor takes taps while a timeline search is active.
    var hidden = false
}

// MARK: - Spring (response 0.45 / damping 0.8, matching the web prototype)

struct OrbitSpring {
    var x: Double
    var v = 0.0
    var target: Double
    init(_ v: Double) { x = v; target = v }
    mutating func step(_ dt: Double) {
        let w = 2 * Double.pi / 0.45, z = 0.8
        let a = w*w*(target - x) - 2*z*w*v
        v += a*dt; x += v*dt
    }
}

// MARK: - Engine (holds physics state across frames)

@Observable
final class OrbitEngine {
    enum Mode { case sphere, timeline, search }

    // Only these drive SwiftUI overlays; kept tiny so per-frame mutation below
    // never invalidates the view (the Canvas repaints via TimelineView anyway).
    var mode: Mode = .sphere
    var inboxCueVisible = false

    // Per-frame / gesture internals — ignored by Observation to avoid churn.
    @ObservationIgnored var nodes: [OrbitNode] = []
    /// Index pairs of neighbouring nodes on the sphere. Fixed topology (sphere
    /// placement never changes), so it's computed once per sync and only redrawn.
    @ObservationIgnored private(set) var links: [(a: Int, b: Int)] = []
    @ObservationIgnored var query: String = ""
    /// Search column metrics, solved once per frame in `step()` and read by the
    /// draw pass so layout and labels can never disagree about the spacing.
    @ObservationIgnored private(set) var searchNodeR: Double = 20
    @ObservationIgnored private(set) var searchShowFragment = true
    @ObservationIgnored private var morph = OrbitSpring(0)
    @ObservationIgnored private var zoom = OrbitSpring(1)
    @ObservationIgnored private var searchAmt = OrbitSpring(0)
    @ObservationIgnored private var rotX = 0.0
    @ObservationIgnored private var rotY = 0.0
    /// Observed: true when the chat list is at/near the top. Drives the search
    /// bar's collapse-on-scroll (tlScroll itself is ignored, so can't).
    var atListTop = true
    @ObservationIgnored var velX = 0.0
    @ObservationIgnored var velY = 0.0
    @ObservationIgnored var tlScroll = 0.0
    @ObservationIgnored var tlScrollV = 0.0
    @ObservationIgnored private var slotOf: [String: Int] = [:]
    @ObservationIgnored private var slotCapacity = 0
    // Paging between globes: 0 = the automatic "recent" globe, 1 = the curated
    // "circle" globe (you at the centre, the people you pinned branching off).
    var page = 0
    static let pageCount = 2
    /// Sentinel id for the "+" spoke on the curated globe — a branch to the
    /// add-contact menu, not a real contact.
    static let addNodeID = "orbit.add"
    @ObservationIgnored private var raw: [Contact] = []
    @ObservationIgnored private var slide = OrbitSpring(0)   // horizontal entry offset, px
    /// Where the globe is turning itself to, if anywhere.
    @ObservationIgnored private var focusRot: (x: Double, y: Double)?
    @ObservationIgnored private var lastFocusAt: Date?
    @ObservationIgnored private var recentArrivals: [Date] = []
    /// Last-seen message time per contact — how an arrival is detected.
    @ObservationIgnored private var seenLastTime: [String: Date] = [:]
    @ObservationIgnored private var lastTick: Date?
    /// Current frame time, stamped in step() so the Canvas draw can age effects.
    @ObservationIgnored var now = Date()
    /// When each contact's last incoming message landed — drives the arrival
    /// pulse ring + the unread-badge pop in the draw.
    @ObservationIgnored var arrivalAt: [String: Date] = [:]
    @ObservationIgnored private(set) var size: CGSize = .zero
    @ObservationIgnored let reduced: Bool

    /// How many contacts the globe may hold. The sphere has a fixed area on
    /// screen, so past this the nodes crowd and stop being aimable. 16 keeps
    /// neighbours ~45° apart — the practical ceiling before the far hemisphere
    /// packs together in projection and labels can't keep up.
    static let maxSphereNodes = 16

    /// How far back "you talk often" looks. Two weeks: long enough to survive a
    /// quiet weekend, short enough that a finished conversation stops counting.
    static let freqWindow: TimeInterval = 14 * 86_400

    /// Floor of the far-side dimming. With only a handful of nodes the back is
    /// worth showing; as the globe fills, the far hemisphere is mostly what you
    /// collide with, so it fades much further out of the way.
    var farFloor: Double {
        let n = Double(nodes.filter(\.onSphere).count)
        let t = clampd((n - 6) / Double(Self.maxSphereNodes - 6), 0, 1)
        return lerp(0.24, 0.07, t)
    }

    init(reduced: Bool) { self.reduced = reduced }

    func sync(contacts: [Contact]) {
        raw = contacts
        rebuild()
    }

    /// Slide to another globe. New content enters from the side; rotation resets
    /// so each globe presents its front pole.
    func goToPage(_ p: Int) {
        guard p != page, p >= 0, p < Self.pageCount else { return }
        let dir = p > page ? 1.0 : -1.0
        page = p
        rebuild()
        rotX = 0; rotY = 0; velX = 0; velY = 0
        zoom.x = 1; zoom.target = 1            // each globe presents at its native scale
        slide.x = dir * Double(size.width)
        slide.target = 0
    }

    private func rebuild() {
        let built = page == 0 ? buildAutoGlobe() : buildCircleGlobe()
        // Preserve on-screen positions for nodes that survive a rebuild so they
        // don't jump; new nodes fall into their computed spot.
        var prev: [String: OrbitNode] = [:]
        for n in nodes { prev[n.contactID] = n }
        var next = built
        for i in next.indices {
            if let p = prev[next[i].contactID] {
                next[i].px = p.px; next[i].py = p.py; next[i].size = p.size; next[i].depth = p.depth
            }
        }
        nodes = next
        // A rebuild (arrival / page) reset rows to natural order — re-apply the
        // chat-list filter if a timeline search is active so it doesn't unfilter.
        if timelineSearching { applyTimelineFilter() }

        // Cue + arrival-turn are properties of the automatic globe only.
        if page == 0 {
            let unreadChats = next.filter { $0.unread > 0 }.count
            // NOTE: previously, >5 unread force-collapsed the globe to morph 0.26
            // on every (re)build — including cold open — and pinned target there
            // too, so it never settled back. It read as a broken sphere (nodes
            // pulled inside toward their list rows) until the user toggled to the
            // timeline and back. The globe now always opens as a full sphere; the
            // unread hint lives in the pull cue (refreshCue), not in the geometry.
            refreshCue(unreadChats: unreadChats)
            noticeArrivals(next)
        } else {
            inboxCueVisible = false
        }
    }

    /// A star node for the curated globe: you in the middle, each pinned contact
    /// wired straight to you. Grows a spoke per contact you add to your circle.
    private func buildCircleGlobe() -> [OrbitNode] {
        let selfC = raw.first(where: \.isSelf)
        // The circle globe is its OWN collection (inCircle), not the favourites.
        let favs = raw.filter { !$0.isSelf && $0.inCircle }
        func node(_ c: Contact, isSelf: Bool) -> OrbitNode {
            let last = c.lastMessage
            // Node labels are drawn in Canvas from a plain String, which does not
            // auto-localize the way a SwiftUI Text literal would — so the fixed
            // ones are resolved through the catalog explicitly here.
            let name = isSelf ? String(localized: "Вы") : c.primaryName
            var fresh = 0.0
            if let last, !last.isOutgoing {
                let m = max(0, Date().timeIntervalSince(last.sentAt)/60)
                fresh = clampd(1 - log(1 + m)/log(1 + 1440), 0, 1)
            }
            return OrbitNode(
                contactID: c.id, name: name,
                initials: String(name.prefix(1)).uppercased(),
                tone: isSelf ? Color(white: 0.42) : Orbit.tones[abs(c.id.hashValue) % Orbit.tones.count],
                unread: c.unreadCount, freshness: fresh,
                lastText: last?.body ?? "", note: isSelf ? "" : c.myNote,
                lastTime: last?.sentAt ?? c.createdAt,
                lastIncoming: last.map { !$0.isOutgoing } ?? false,
                freq: isSelf ? 1 : 0.6, isFavourite: !isSelf && c.isFavourite, row: 0)
        }
        var built: [OrbitNode] = []
        // You are always the centre, even before a Saved-Messages contact exists.
        if let selfC {
            built.append(node(selfC, isSelf: true))
        } else {
            let you = String(localized: "Вы")
            built.append(OrbitNode(
                contactID: "orbit.self", name: you, initials: String(you.prefix(1)).uppercased(),
                tone: Color(white: 0.42), unread: 0, freshness: 0,
                lastText: "", lastTime: Date(), lastIncoming: false,
                freq: 1, isFavourite: false, row: 0))
        }
        built.append(contentsOf: favs.map { node($0, isSelf: false) })
        // The curated globe always carries a control spoke into the circle picker.
        // While there's room it's a "+" to add someone; once the circle is full it
        // flips to a "−" that says "remove one to make space" — same picker, which
        // both adds and removes.
        let full = favs.count >= Contact.maxCircle
        built.append(OrbitNode(
            contactID: Self.addNodeID,
            name: full ? String(localized: "Убрать") : String(localized: "Добавить"),
            initials: full ? "−" : "+",
            tone: Color(white: 0.14), unread: 0, freshness: 0,
            lastText: "", lastTime: Date(), lastIncoming: false,
            freq: 0, isFavourite: false, row: 0))
        for i in built.indices { built[i].onSphere = true; built[i].row = i }

        // Hub and spokes, not a scattered sphere: YOU at the exact front pole so
        // you project to the centre, everyone else on a ring around you. It still
        // rotates like a globe, but at rest it reads as "you, with your circle
        // branching off". Grows a spoke per contact you pin.
        let ring = 65.0 * .pi/180           // polar angle of the ring from the pole
        let spokes = max(1, built.count - 1)
        for i in built.indices {
            if i == 0 {                      // you
                built[i].sx = 0; built[i].sy = 0; built[i].sz = 1
            } else {
                let phi = 2 * Double.pi * Double(i - 1) / Double(spokes) - .pi/2
                let r = sin(ring)
                built[i].sx = cos(phi)*r
                built[i].sy = sin(phi)*r
                built[i].sz = cos(ring)
            }
        }
        // Every spoke goes to you (index 0), not to neighbours.
        links = built.count > 1 ? (1..<built.count).map { (a: 0, b: $0) } : []
        return built
    }

    // Build the automatic globe from the live contacts (skips the self chat).
    private func buildAutoGlobe() -> [OrbitNode] {
        let contacts = raw
        let real = contacts.filter { !$0.isSelf }
        // "Often" means often LATELY. Counting whole-history volume left an old
        // chat wearing a heavy ring forever, long after you stopped talking.
        let horizon = Date().addingTimeInterval(-Self.freqWindow)
        func recentCount(_ c: Contact) -> Int {
            c.messages.reduce(0) { $0 + ($1.sentAt > horizon ? 1 : 0) }
        }
        let maxRecent = max(1, real.map(recentCount).max() ?? 1)
        let ordered = real.enumerated().map { (i, c) -> OrbitNode in
            let last = c.lastMessage
            let name = c.primaryName
            let freq = Double(recentCount(c)) / Double(maxRecent)
            // Only THEIR messages count — your own replies aren't news.
            //
            // Logarithmic, not a power curve: message age spans minutes to a day,
            // and what you compare is ratios (2 min vs 20 min vs 2 hours), not
            // absolute deltas. A pow(0.35) ramp squeezed everything under an hour
            // into an 18% size band — unreadable. Log spreads the same range over
            // 2.1x of bubble.
            var fresh = 0.0
            if let last, !last.isOutgoing {
                let minutes = max(0, Date().timeIntervalSince(last.sentAt) / 60)
                fresh = clampd(1 - log(1 + minutes)/log(1 + 1440), 0, 1)
            }
            return OrbitNode(
                contactID: c.id,
                name: name,
                initials: String(name.prefix(1)).uppercased(),
                tone: Orbit.tones[abs(c.id.hashValue) % Orbit.tones.count],
                unread: c.unreadCount,
                freshness: fresh,
                lastText: last?.body ?? "",
                note: c.myNote,
                lastTime: last?.sentAt ?? c.createdAt,
                lastIncoming: last.map { !$0.isOutgoing } ?? false,
                freq: freq,
                isFavourite: c.isFavourite,
                row: i)
        }
        var built = ordered
        // timeline order by most-recent message
        let byTime = built.enumerated().sorted { $0.element.lastTime > $1.element.lastTime }
        for (rank, pair) in byTime.enumerated() { built[pair.offset].row = rank }

        // Membership: pinned contacts first — a favourite never ages off the
        // globe, that's the whole point of pinning one. The remaining slots go
        // to whoever wrote most recently, so a fresh message still always lands
        // on the sphere.
        //
        // The cap is still absolute: it is what keeps nodes far enough apart to
        // aim at. If favourites ever outnumber it, the most recent favourites
        // hold the slots — see maxSphereNodes.
        var members = Set<Int>()
        let byRecency = built.indices.sorted { built[$0].row < built[$1].row }
        // Favourites are capped (Contact.maxFavourites) so they can never swallow
        // the whole auto globe and lock fresh arrivals out. Circle membership is a
        // different thing entirely and has no bearing here.
        var pinned = 0
        for i in byRecency where built[i].isFavourite && pinned < Contact.maxFavourites {
            members.insert(i); pinned += 1
        }
        for i in byRecency where members.count < Self.maxSphereNodes {
            members.insert(i)
        }

        // Cold start: with fewer than two contacts the only thing worth showing
        // is the way in. A "+" node sits on the globe as the add-contact branch
        // and removes itself the instant you have 2+ people — from then on the
        // automatic globe is nothing but real contacts. freq 0 parks it in the
        // last free slot (slot 0 when it's the only node, so the very first empty
        // globe is a single "+" dead-centre).
        if real.count < 2 {
            built.append(OrbitNode(
                contactID: Self.addNodeID, name: String(localized: "Добавить контакт"), initials: "+",
                tone: Color(white: 0.14), unread: 0, freshness: 0,
                lastText: "", lastTime: .distantPast, lastIncoming: false,
                freq: 0, isFavourite: false, row: built.count))
            members.insert(built.count - 1)
        }

        for i in built.indices { built[i].onSphere = members.contains(i) }
        placeOnSphere(&built)
        links = linkNeighbours(built)
        return built
    }

    /// Spot messages that landed since the last sync and, if it's a lone arrival,
    /// turn the globe to face whoever sent it — including a contact who had aged
    /// out of the sphere and just earned their way back on.
    private func noticeArrivals(_ built: [OrbitNode]) {
        let first = seenLastTime.isEmpty
        var arrived: [OrbitNode] = []
        for n in built {
            if let seen = seenLastTime[n.contactID], n.lastTime > seen, n.lastIncoming {
                arrived.append(n)
            }
            seenLastTime[n.contactID] = n.lastTime
        }
        // Stamp every arrival so the draw can pulse its node + pop its badge.
        if !first {
            let t = Date()
            for n in arrived { arrivalAt[n.contactID] = t }
        }

        // Nothing is "new" on the very first sync — otherwise the globe would
        // spin the moment you opened the app.
        guard !first, let newest = arrived.max(by: { $0.lastTime < $1.lastTime }) else { return }

        let now = Date()
        recentArrivals.append(now)
        recentArrivals.removeAll { now.timeIntervalSince($0) > 10 }

        // Spam: a burst of messages must not send the globe spinning between
        // senders. Past a few arrivals in ten seconds it stops chasing entirely —
        // the unread counts already say who wants you.
        guard recentArrivals.count <= 3 else { focusRot = nil; return }
        // And never more than one turn every few seconds, even below that.
        if let last = lastFocusAt, now.timeIntervalSince(last) < 4 { return }
        // Only the globe turns; don't yank the list or a search out from under you.
        guard mode == .sphere, newest.onSphere,
              let node = built.first(where: { $0.contactID == newest.contactID })
        else { return }

        lastFocusAt = now
        focusRot = rotationFacing(node)
    }

    /// Rotation that brings a node onto the camera axis. Choose rotY to zero the
    /// node's x, then rotX to lift it to z = 1.
    private func rotationFacing(_ n: OrbitNode) -> (x: Double, y: Double) {
        let ry = atan2(n.sx, n.sz)
        let z1 = (n.sx*n.sx + n.sz*n.sz).squareRoot()
        let rx = clampd(atan2(n.sy, z1), -1.15, 1.15)
        return (rx, ry)
    }

    private func refreshCue(unreadChats: Int? = nil) {
        let count = unreadChats ?? nodes.filter { $0.unread > 0 }.count
        inboxCueVisible = mode == .sphere && morph.target < 0.5 && count > 5
    }

    /// The pull-down affordance: a chevron always present on the resting sphere so
    /// it's discoverable that the chats feed lives one pull away. `inboxCueVisible`
    /// is the louder version of the same hint (lots of unread waiting); this is the
    /// quiet baseline that's there even with nothing unread.
    var pullHintVisible: Bool { mode == .sphere && morph.target < 0.5 }

    // Fibonacci sphere, ordered so the most-frequent contacts land on the pole
    // that faces the viewer.
    //
    // The fibonacci walk builds its pole along +y, so the sphere is tilted to
    // bring that pole to the camera (+z). The tilt used to be -0.62 rad, which
    // rotated the pole to z = -0.58 — i.e. it pushed the people you talk to MOST
    // to the FAR side of the globe, where perspective made them the smallest and
    // dimmest nodes on screen. Exactly backwards. π/2 puts the pole dead-on; the
    // extra 0.30 tips it slightly so you can see over the top of the globe.
    private func placeOnSphere(_ ns: inout [OrbitNode]) {
        let members = ns.indices.filter { ns[$0].onSphere }
        // The lattice is a FIXED 16-slot constellation — the "ideal" full globe.
        // Its geometry never depends on how many slots are lit right now, so
        // growth is deterministic: slot 0 is always the same spot on screen,
        // adding the Nth contact never moves the first N-1, and every count from
        // 1 to 16 is just a partially-filled version of the same shape. (Earlier
        // the lattice was sized to the member count, so y = 1-(2k+1)/count — one
        // new contact re-derived every position and the whole globe jumped.)
        let N = Self.maxSphereNodes

        // Slots are STICKY. A contact keeps the slot it was given; a newcomer
        // inherits the lowest slot someone vacated. Combined with the fixed
        // lattice above, this is what makes each growth stage reproducible.
        let memberIDs = Set(members.map { ns[$0].contactID })
        slotOf = slotOf.filter { memberIDs.contains($0.key) }
        if slotCapacity != N { slotOf.removeAll(); slotCapacity = N }
        var free = Set(0..<N).subtracting(slotOf.values)
        // Slot 0 is the front pole, so the most frequent newcomer takes the
        // frontmost opening — which is also where a fresh arrival belongs.
        for idx in members.filter({ slotOf[ns[$0].contactID] == nil })
                          .sorted(by: { ns[$0].freq > ns[$1].freq }) {
            guard let slot = free.min() else { break }
            free.remove(slot)
            slotOf[ns[idx].contactID] = slot
        }

        // Offset Fibonacci lattice: y = 1 - (2k+1)/N, NOT 1 - 2k/(N-1). The latter
        // parks slot 0 exactly ON the pole, where the latitude circle has zero
        // radius — so slot 1 had nowhere to go but right next to it. Measured at
        // N=12: 35.1° between slots 0 and 1, versus 52.9° worst-case here. That
        // put the two contacts you talk to most on top of each other, every time.
        let ga = Double.pi * (3 - 5.0.squareRoot())
        func raw(_ k: Int) -> (x: Double, y: Double, z: Double) {
            let y = 1 - Double(2*k + 1)/Double(N)
            let r = (1 - y*y).squareRoot()
            let th = ga * Double(k)
            return (cos(th)*r, y, sin(th)*r)
        }

        // Aim SLOT 0 at the camera, by rotating the whole lattice rigidly. The
        // offset above buys its spacing by keeping every point OFF the pole, so
        // slot 0 sits 20.4° away from it — a plain tilt therefore left the first
        // contact (and the lone "+" on an empty globe) hanging off to one side.
        // A rigid rotation preserves every relative angle and makes slot 0 mean
        // exactly "dead ahead".
        //
        // It also retires the old hand-tuned `tilt = π/2 + 0.30`. That 0.30 was
        // there to tip the globe so you could see over its top; with slot 0 on
        // the axis, the lattice's own pole lands 20.4° above it and you get that
        // for free — derived instead of dialled in.
        let v0 = raw(0)
        let ry = -atan2(v0.x, v0.z)
        let rho = (v0.x*v0.x + v0.z*v0.z).squareRoot()
        let rx = atan2(v0.y, rho)

        for idx in members {
            // Position comes from the node's own slot, never from its position in
            // some list — that's what makes it stick.
            guard let k = slotOf[ns[idx].contactID] else { continue }
            let v = raw(k)
            let x1 =  v.x*cos(ry) + v.z*sin(ry)
            let z1 = -v.x*sin(ry) + v.z*cos(ry)
            ns[idx].sx = x1
            ns[idx].sy = v.y*cos(rx) - z1*sin(rx)
            ns[idx].sz = v.y*sin(rx) + z1*cos(rx)
        }
    }

    /// Link each node to its 3 nearest neighbours *on the sphere* (3D distance,
    /// not screen distance — screen distance would wire together nodes that are
    /// actually on opposite faces). Deduped, so each edge is drawn once.
    private func linkNeighbours(_ ns: [OrbitNode]) -> [(a: Int, b: Int)] {
        let members = ns.indices.filter { ns[$0].onSphere }
        guard members.count > 1 else { return [] }
        let k = min(3, members.count - 1)
        var seen = Set<Int>()
        var out: [(a: Int, b: Int)] = []
        for i in members {
            let nearest = members
                .filter { $0 != i }
                .sorted { sqDist(ns[i], ns[$0]) < sqDist(ns[i], ns[$1]) }
                .prefix(k)
            for j in nearest {
                let lo = min(i, j), hi = max(i, j)
                let key = lo * 10_000 + hi
                if seen.insert(key).inserted { out.append((lo, hi)) }
            }
        }
        return out
    }
    private func sqDist(_ a: OrbitNode, _ b: OrbitNode) -> Double {
        let dx = a.sx - b.sx, dy = a.sy - b.sy, dz = a.sz - b.sz
        return dx*dx + dy*dy + dz*dz
    }

    // MARK: transitions
    func toTimeline() {
        mode = .timeline; morph.target = 1; focusRot = nil
        tlScroll = 0; tlScrollV = 0     // every pull-down opens at the newest chat
        refreshCue()
    }
    func toSphere()   { mode = .sphere;   morph.target = 0; refreshCue() }
    /// Opening search only freezes the scene — the nodes hold their places. They
    /// converge on the query as you type; with an empty query every node
    /// "matches", which used to stack all of them into one off-screen column.
    func openSearch() {
        mode = .search; focusRot = nil
        searchAmt.target = 0    // freeze in place; nodes only move once you type
        morph.target = 0        // collapse any half-open timeline — it fights the column
        query = ""
        refreshCue()
    }
    func closeSearch(){ mode = .sphere; searchAmt.target = 0; query = ""; msgMatch = [:]; refreshCue() }

    /// Per-query cache: contactID → the matching message (most recent) when a
    /// contact matched on MESSAGE TEXT (not just its name). Rebuilt on each
    /// keystroke so search covers the whole conversation, not only the last line,
    /// and so a tap can jump straight to the message that matched.
    @ObservationIgnored private var msgMatch: [String: (id: String, body: String)] = [:]

    /// Rebuild the message-match cache for a query (shared by both searches).
    private func rescan(_ q: String) {
        msgMatch = [:]
        guard !q.isEmpty else { return }
        for c in raw where !c.isSelf {
            // Search every text message (photos carry a tx id in `body`, not text).
            // Surface the MOST RECENT match so the jump lands on the latest hit.
            if let hit = c.messages
                .filter({ $0.photoKey == nil && $0.body.range(of: q, options: .caseInsensitive) != nil })
                .max(by: { $0.sentAt < $1.sentAt }) {
                msgMatch[c.id] = (hit.id, hit.body)
            }
        }
    }

    /// GLOBE search: freezes the scene and morphs matches into a column.
    func setQuery(_ q: String) {
        query = q
        searchAmt.target = q.isEmpty ? 0 : 1
        rescan(q)
    }

    // ---- Chat-list (timeline) search — a SEPARATE search that stays in the list
    // and filters rows in place; it never switches to the globe. -----------------

    @ObservationIgnored var timelineSearching = false

    func setTimelineQuery(_ q: String) {
        query = q
        rescan(q)
        timelineSearching = !q.isEmpty
        applyTimelineFilter()
    }
    func endTimelineSearch() {
        timelineSearching = false; query = ""; msgMatch = [:]
        applyTimelineFilter()
    }
    /// Re-rank timeline rows: when filtering, matches pack to the top (0…k) and
    /// non-matches are parked far below the fold (off-screen, untappable, and out
    /// of scroll range). With no filter, rows return to their natural time order.
    private func applyTimelineFilter() {
        if !timelineSearching {
            let byTime = nodes.enumerated().sorted { $0.element.lastTime > $1.element.lastTime }
            for (rank, pair) in byTime.enumerated() {
                nodes[pair.offset].row = rank; nodes[pair.offset].hidden = false
            }
            tlScroll = 0; tlScrollV = 0
            return
        }
        // Matches pack to the top with real (small) row numbers so the morph
        // stagger stays sane; non-matches keep contiguous rows too but are HIDDEN
        // (forced off-screen in step). Parking them at huge row numbers instead
        // gave them a giant morph delay, so they never left their sphere position
        // and the globe bled through the filtered list.
        let vis = nodes.indices.filter { matches(nodes[$0]) }
            .sorted { nodes[$0].lastTime > nodes[$1].lastTime }
        for (rank, i) in vis.enumerated() { nodes[i].row = rank; nodes[i].hidden = false }
        var r = vis.count
        for i in nodes.indices where !matches(nodes[i]) {
            nodes[i].row = r; nodes[i].hidden = true; r += 1
        }
        tlScroll = 0; tlScrollV = 0
    }
    /// Row count that bounds timeline scrolling — only the matches while filtering.
    private var timelineVisibleRows: Int {
        timelineSearching ? nodes.reduce(0) { $0 + (matches($1) ? 1 : 0) } : nodes.count
    }

    func matches(_ n: OrbitNode) -> Bool {
        guard !query.isEmpty else { return true }
        return n.name.range(of: query, options: .caseInsensitive) != nil
            || msgMatch[n.contactID] != nil
    }
    /// The id of the message a tap should scroll to, if this contact matched on
    /// message text (nil for a pure name match — just open at the bottom).
    func matchedMessageID(for contactID: String) -> String? { msgMatch[contactID]?.id }
    /// The matching message text, shown under the name in the result column when
    /// the hit came from a message rather than the name.
    func matchFragment(_ n: OrbitNode) -> String? {
        guard !query.isEmpty,
              n.name.range(of: query, options: .caseInsensitive) == nil,
              let hit = msgMatch[n.contactID]
        else { return nil }
        return hit.body
    }
    var searchAmount: Double { searchAmt.x }

    // MARK: per-frame update + layout (called from Canvas each frame)
    func step(date: Date, size: CGSize) {
        self.size = size
        self.now = date
        let dt = min(lastTick.map { date.timeIntervalSince($0) } ?? 0, 0.05)
        lastTick = date

        morph.step(dt); zoom.step(dt); searchAmt.step(dt); slide.step(dt)
        if mode == .sphere, !rotatable {
            // Static globe: everyone is on the front face, so pin it dead-on and
            // drop any leftover spin/auto-turn (e.g. an arrival trying to face
            // its sender when the sender is already looking at you).
            rotX = 0; rotY = 0; velX = 0; velY = 0; focusRot = nil
        } else if mode == .sphere {
            if let f = focusRot {
                // Ease onto the sender. Take the shortest way round rather than
                // unwinding the long way through accumulated rotation.
                velX = 0; velY = 0
                var dy = f.y - rotY
                dy = atan2(sin(dy), cos(dy))
                let k = 1 - exp(-dt/0.38)
                rotY += dy*k
                rotX += (f.x - rotX)*k
                if abs(dy) < 0.008, abs(f.x - rotX) < 0.008 { focusRot = nil }
            } else if zoomActive {
                velX = 0; velY = 0          // hold still through the pinch
            } else {
                rotY += velY*dt; rotX += velX*dt
                velY *= pow(0.02, dt); velX *= pow(0.02, dt)
            }
            rotX = clampd(rotX, -1.15, 1.15)
            // A near-empty globe has all its nodes clustered on the front face
            // (slots 0,1,2… fill the front first). A free 360° yaw would drag the
            // only node(s) round into the empty back hemisphere and the screen
            // would go blank — which reads as the globe breaking. So cap the yaw
            // to a range that OPENS UP as the globe fills: barely any swing with
            // one node, full spin once there's a real sphere's worth (≥8) to keep
            // something always facing you.
            let live = nodes.reduce(0) { $0 + ($1.onSphere ? 1 : 0) }
            if live < 8 {
                let lim = lerp(0.75, .pi, Double(max(0, live - 1))/7)
                if abs(rotY) > lim { rotY = clampd(rotY, -lim, lim); velY = 0 }
            }
        }
        // Momentum after a flick. A high decay base = a long, slow coast: 0.001/s
        // slammed to a stop instantly, 0.1/s was still too short to feel, 0.35/s
        // glides well past the release and eases out like a real scroll view.
        tlScroll += tlScrollV*dt; tlScrollV *= pow(0.35, dt)
        clampScroll()
        // Collapse the chat-list search bar once you scroll off the top, restore
        // it at the very top. `atListTop` is observed, and step() runs INSIDE the
        // Canvas render — mutating it there is "state change during view update"
        // and hard-hangs the app, so defer the flip to the next runloop. Hysteresis
        // (hide past −30, show again near 0) stops it flip-flopping at a threshold.
        let newTop = atListTop ? (tlScroll > -30) : (tlScroll > -6)
        if newTop != atListTop {
            DispatchQueue.main.async { [weak self] in self?.atListTop = newTop }
        }

        let W = Double(size.width), H = Double(size.height)
        let CX = W/2, CY = H/2
        let R = min(W, H) * 0.42 * zoom.x
        let mt = morph.x, sf = searchAmt.x
        let matchTotal = max(1, nodes.filter(matches).count)
        var mi = 0

        // Solve the match column from the label block's real height instead of a
        // guessed step. Below a node's centre sits: its radius, a gap, the name,
        // and (optionally) a message fragment. Above the NEXT node's centre sits
        // its radius plus the unread badge that pokes out past it. Hand-tuned
        // steps kept letting the fragment graze the disc underneath.
        let colTop = 150.0                    // under the search field
        let colBottom = H * 0.64              // where the keyboard starts
        let colAvail = max(120.0, colBottom - colTop)
        let perMatch = colAvail / Double(matchTotal)
        let nameH = 20.0, fragH = 18.0, gap = 7.0, badgeOut = 12.0
        // Try richest layout first, fall back as the column gets crowded.
        if perMatch >= 20 + gap + nameH + fragH + 20 + badgeOut {
            searchNodeR = 20; searchShowFragment = true
        } else if perMatch >= 18 + gap + nameH + 18 + badgeOut {
            searchNodeR = 18; searchShowFragment = false
        } else {
            searchNodeR = 14; searchShowFragment = false
        }
        let block = searchNodeR + gap + nameH + (searchShowFragment ? fragH : 0)
        let colStep = max(block + searchNodeR + badgeOut, min(perMatch, 112))
        let colH = Double(matchTotal - 1) * colStep
        let colStart = colTop + max(0, (colAvail - colH)/2)

        for i in nodes.indices {
            var n = nodes[i]
            // sphere projection
            let x = n.sx, y = n.sy, z = n.sz
            let x1 = x*cos(rotY) - z*sin(rotY)
            let z1 = x*sin(rotY) + z*cos(rotY)
            let y2 = y*cos(rotX) - z1*sin(rotX)
            let z2 = y*sin(rotX) + z1*cos(rotX)
            var depth = (z2 + 1)/2

            // Orthographic on purpose. A perspective divide was tried here and
            // made things worse: it scales x,y, but a node near either pole has
            // x,y ≈ 0 and lands at the centre under ANY camera — so it never
            // fixed the front/back overlap it was meant to fix. Meanwhile the
            // widest part of the disc (the silhouette, z = 0) gets a divide of
            // exactly 1.0, i.e. no spread at all, while the radius had to shrink
            // to make room for a fan-out that only ever reached ×1.085. Net
            // effect: a 30% smaller, more crowded globe. Depth is carried by
            // scale, opacity and the mesh instead.
            // slide.x carries the whole globe in from the side on a page change.
            var sxp = CX + x1*R + slide.x, syp = CY + y2*R
            var baseR = 15.0 * lerp(0.52, 1.12, depth)

            // List-only contacts never take a place on the globe: they wait at
            // their row and fade in with it. Parking them at the row means the
            // morph has nothing to animate for them — they belong to the list.
            if !n.onSphere {
                let rp = timelineRow(n, W: W, H: H, CY: CY)
                sxp = rp.x; syp = rp.y; baseR = 22
                depth = 1      // it has no place on the globe, so it owes it no depth
            }
            var rad = baseR, fade = 0.0

            var rowAlpha = 0.0
            var dpth = depth
            if mt > 0.001 {
                let rp = timelineRow(n, W: W, H: H, CY: CY)
                // Cascade top→bottom, 16 ms/element. Normalized so the whole
                // stagger + each node's own span fits exactly in mt 0…1 —
                // otherwise early rows race ahead (row 0 hit 78% at mt=0.26).
                let delay = Double(n.row)*0.016
                let span = 0.5
                let stagger = Double(max(0, nodes.count - 1))*0.016
                let tt = reduced ? mt : easeInOut(clampd((mt*(stagger + span) - delay)/span, 0, 1))
                sxp = lerp(sxp, rp.x, tt); syp = lerp(syp, rp.y, tt)
                rad = lerp(rad, 22, tt); dpth = lerp(depth, 1, tt); rowAlpha = tt
            }

            // Search is applied LAST, on top of whatever layout the morph
            // produced. It used to run first and the morph then overwrote it —
            // opening search from the half-collapsed state (>5 unread) dragged
            // the matches back toward their rows and the column collapsed into a
            // clump.
            if sf > 0.001 {
                let m = matches(n)
                var tx = 0.0, ty = 0.0
                var tr = rad
                if m {
                    tx = CX
                    ty = colStart + Double(mi)*colStep
                    tr = searchNodeR
                    mi += 1
                } else {
                    let ang = Double(i)/Double(max(1, nodes.count)) * .pi*2
                    let far = max(W, H)*0.75
                    tx = CX + cos(ang)*far; ty = CY + sin(ang)*far
                }
                sxp = lerp(sxp, tx, sf); syp = lerp(syp, ty, sf); rad = lerp(rad, tr, sf)
                dpth = lerp(dpth, 1, sf)          // a focused match is never dimmed by depth
                rowAlpha = lerp(rowAlpha, 0, sf)  // and never wears row chrome
                fade = m ? 0 : sf*0.9
            }

            n.px = sxp; n.py = syp; n.size = rad; n.depth = dpth; n.fade = fade; n.rowAlpha = rowAlpha
            // Filtered out by the chat-list search: shove it off-screen and make it
            // fully transparent, whatever the morph produced.
            if n.hidden { n.px = -100_000; n.py = -100_000; n.fade = 1; n.rowAlpha = 0 }
            nodes[i] = n
        }
    }

    // Row 0 sits just under the chrome — the list always opens at its top.
    private static let rowH = 76.0
    private static let listTop = 206.0      // clears the brand+nick bar AND the search bar
    private static let listBottom = 64.0    // clears the bottom hint

    func timelineRow(_ n: OrbitNode, W: Double, H: Double, CY: Double) -> (x: Double, y: Double) {
        // slide.x carries the whole feed in from the side on a page change, so
        // switching between the two chat feeds animates instead of snapping.
        let x = W*0.5 - min(260, W*0.40) + slide.x
        return (x, Self.listTop + Double(n.row)*Self.rowH + tlScroll)
    }

    private func clampScroll() {
        // tlScroll: 0 = pinned to the first row, negative = scrolled down.
        let total = Double(timelineVisibleRows)*Self.rowH
        let visible = Double(size.height) - Self.listTop - Self.listBottom
        let minS = min(0, -(total - visible))
        if tlScroll > 0 { tlScroll = 0; tlScrollV = 0 }
        if tlScroll < minS { tlScroll = minS; tlScrollV = 0 }
    }

    /// The globe only spins on the automatic globe (page 0), and only once it
    /// holds enough people that some are hidden on the far side. Up to four
    /// contacts the fixed lattice keeps every node on the front hemisphere (min
    /// z ≈ +0.6, all plainly visible), so there's nothing to rotate to. The
    /// curated circle (page 1) is a static front-facing ring — never rotatable.
    var rotatable: Bool {
        page == 0 && nodes.reduce(0) { $0 + ($1.onSphere ? 1 : 0) } > 4
    }

    /// When a pinch last changed the zoom. A pinch is two fingers, and the drag
    /// gesture's one-finger centroid wanders between them — feeding bogus deltas
    /// into rotate() and flinging the globe. Rather than fight gesture arbitration
    /// (which lets the drag claim the touch before the magnify is recognised), any
    /// rotation/inertia is simply suppressed while a zoom is active or just-ended.
    @ObservationIgnored var lastZoomAt: Date?
    var zoomActive: Bool {
        guard let t = lastZoomAt else { return false }
        return Date().timeIntervalSince(t) < 0.35
    }

    // gestures
    func rotate(dx: Double, dy: Double) {
        guard rotatable, !zoomActive else { return }
        focusRot = nil          // touching the globe cancels any auto-turn
        // Direct manipulation: the grabbed front of the globe follows the finger.
        // The projection maps +rotY → front content moves LEFT, so a rightward
        // drag (dx > 0) must DECREASE rotY (and likewise for the vertical axis) —
        // otherwise the globe spins opposite to the swipe.
        rotY -= dx*0.006; rotX = clampd(rotX - dy*0.006, -1.15, 1.15)
        velY = -dx*0.35; velX = -dy*0.35
    }
    func scrollTimeline(dy: Double) { tlScroll += dy; tlScrollV = dy*18; clampScroll() }
    func zoom(by delta: Double) {
        zoom.target = clampd(zoom.target - delta, 0.7, 2.0)
        lastZoomAt = Date()
        velX = 0; velY = 0          // a pinch never leaves the globe spinning
    }

    func node(at p: CGPoint) -> OrbitNode? {
        // In the timeline a row spans the whole width — the avatar is only its
        // left edge. Hit-testing a small circle around the avatar meant a tap on
        // the name or message text (200pt to the right) matched nothing and the
        // chat never opened. Test the full-width band instead.
        if mode == .timeline {
            for n in nodes where !n.hidden && abs(Double(p.y) - n.py) < Self.rowH/2 {
                return n
            }
            return nil
        }
        // Search: results sit in a flat column at their projected px/py. Hit-test
        // ONLY the matches (non-matches have flown off-screen) and skip the sphere
        // gates — a match that isn't a sphere node (a list-only contact, or one
        // past the 16 sphere slots) was being filtered out here, so the tap missed
        // and fell through to the dismiss scrim: search just closed, no chat.
        if mode == .search {
            // Results sit in a column: a circle with its name (and message
            // fragment) stacked below it. Hit the NEAREST match within a generous
            // radius that covers the whole result — the circle AND its labels — so
            // a tap on the contact opens the chat, and only genuinely empty space
            // (outside every result) falls through to dismiss search.
            var best: OrbitNode?; var bd = Double.greatestFiniteMagnitude
            for n in nodes where matches(n) {
                let d = hypot(Double(p.x) - n.px, Double(p.y) - n.py)
                if d < bd { bd = d; best = n }
            }
            return bd < 96 ? best : nil
        }
        var best: OrbitNode?; var bd = Double.greatestFiniteMagnitude
        for n in nodes {
            if !n.onSphere { continue }
            if n.depth < 0.32 { continue }
            let d = hypot(Double(p.x) - n.px, Double(p.y) - n.py)
            if d < n.size + 6 && d < bd { bd = d; best = n }
        }
        return best
    }
    var breathBase = Date()
    func breath(_ now: Date) -> Double {
        guard !reduced else { return 1 }
        let t = now.timeIntervalSince(breathBase)
        return 0.92 + 0.08*(0.5 + 0.5*sin(t*(2*Double.pi/8)))
    }
}

// MARK: - View

struct OrbitChatsView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(MessageQuotaService.self) private var quota
    @Environment(AvatarService.self) private var avatars
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(ToastManager.self) private var toast
    @Environment(InviteInbox.self) private var invites
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Contact.createdAt, order: .reverse) private var allContacts: [Contact]

    @State private var engine: OrbitEngine?
    @State private var selected: Contact?
    /// When a chat is opened from a MESSAGE search hit, the id of the message to
    /// scroll to and flash. Set right before `selected`, nil for any other open.
    @State private var jumpMessageID: String?
    @State private var quickContact: Contact?
    @State private var profileContact: Contact?   // long-press in the timeline
    @State private var quickText: String = ""
    @State private var searchText: String = ""
    @State private var timelineText: String = ""   // chat-list (in-place) search
    @State private var showAdd = false
    @State private var showProfile = false
    @State private var showPaywall = false
    @State private var deleteCandidate: Contact?   // swipe-left a chat row to delete
    @State private var showCirclePicker = false
    @FocusState private var searchFocused: Bool
    @FocusState private var timelineFocused: Bool
    @FocusState private var quickFocused: Bool
    @State private var dragStart: CGPoint?
    @State private var dragLast: CGPoint?
    @State private var dragMoved: Double = 0
    @State private var dragDx: Double = 0      // accumulated in onChanged — see sceneDrag
    @State private var dragDy: Double = 0
    @State private var isPinching = false      // a magnify is in flight
    @State private var sawPinch = false        // this drag overlapped a pinch → not a rotate/swipe
    @State private var lpWork: DispatchWorkItem?
    @State private var lpFired = false
    @State private var cueBob = false
    @State private var quotaBounce: CGFloat = 1   // spring pop on balance change
    /// Where on screen the quick-reply card grows from and collapses back into —
    /// the node you pressed. Without it the card would scale from the middle of
    /// the screen and read as unrelated to the contact.
    @State private var quickAnchor: UnitPoint = .center
    /// Drives the card's scale explicitly. A `.transition` on the card did not
    /// play on close: removing `quickContact` tears down the whole container, and
    /// a child's transition doesn't run when its parent is the thing being
    /// removed — the card just blinked out. Keeping it mounted and animating the
    /// scale is the only way it can crawl back into the avatar.
    @State private var quickVisible = false

    /// One motion for the whole product: the same spring the scene morph uses
    /// (response 0.45 / damping 0.8). Present, not showy.
    ///
    /// SwiftUI does NOT honour Reduce Motion inside `withAnimation` on its own —
    /// it has to be asked. Under it, travel is replaced by a short fade.
    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.45, dampingFraction: 0.8)
    }
    /// Same rule for the transitions: no flying, just a fade.
    private func grow(from anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.04, anchor: anchor).combined(with: .opacity)
    }
    /// True when a timeline drag began inside the bottom handle zone. In the
    /// timeline, swipe-up is the scroll gesture, so it cannot also mean "leave
    /// for the globe" — reading the whole screen made every scroll a coin flip
    /// on whether you'd get thrown out of the list. Only the handle exits.
    @State private var dragFromHandle = false
    /// A sphere pull-down only opens the chat list when it STARTS in the top strip
    /// (under the bar, where the chevron hint sits). Anywhere else on the sphere a
    /// downward drag just rotates — otherwise every time you spun the globe you
    /// risked being thrown into the timeline.
    @State private var dragFromTop = false

    /// The row a horizontal drag started on, in the timeline — that drag deletes
    /// the chat instead of paging between feeds. Nil = not over a row (or the "+"
    /// control spoke), so paging stays available everywhere else.
    @State private var dragFromRow: OrbitNode?
    /// Live horizontal offset of the row being swiped, so it slides with the
    /// finger before the swipe commits or springs back.
    @State private var rowSwipeDx: Double = 0
    /// True once a drag that STARTED on a row has committed to the horizontal
    /// swipe-to-delete gesture. Until it does, a vertical drag scrolls the list and
    /// a tap opens the chat — the finger almost always lands on a row, so the
    /// gesture must not hijack every touch. Decided by dominant axis in onChanged.
    @State private var rowSwipeEngaged = false
    /// The row currently playing its delete slide-out (id), when it started, and
    /// the offset it started from (where the finger let go). The row slides fully
    /// off-screen over `deleteAnimDur`, then the contact is actually removed and
    /// the list closes the gap. Nil = nothing deleting.
    @State private var deletingID: String?
    @State private var deletingSince: Date?
    @State private var deleteStartDx: Double = 0
    private static let deleteAnimDur: Double = 0.26
    /// Swipe-to-delete threshold (points). Past this on release, the chat deletes.
    private static let deleteSwipeThreshold: Double = 90

    /// Height of the pull-up handle strip at the bottom of the timeline.
    private static let handleZone: Double = 104
    /// Height of the pull-down strip at the top of the sphere (below the bar).
    private static let topZone: Double = 180

    private var activeAddress: String {
        if case let .ready(pk) = wallet.state { return pk }
        return ""
    }
    private var contacts: [Contact] {
        // STRICT per-account isolation: a contact belongs to exactly one account.
        // The old `|| ownerAddress.isEmpty` fallback leaked any empty-owner contact
        // onto EVERY account (a privacy bug). Legacy empty-owner contacts are
        // adopted by the FIRST account on launch (see MainTabView), so nothing is
        // orphaned.
        allContacts.filter { $0.ownerAddress == activeAddress }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // The scene fills the display; chrome below keeps its safe area.
                GeometryReader { geo in
                    ZStack {
                        background
                        if let engine {
                            scene(engine, size: geo.size)
                                .contentShape(Rectangle())
                                .gesture(sceneDrag(size: geo.size))
                                .simultaneousGesture(magnify)
                        }
                    }
                }
                .ignoresSafeArea()

                if let engine { overlays(engine) }
            }
            .onAppear { boot(reduced: reduceMotion) }
            #if DEBUG
            // Screenshot helper: -chatShot <a|b> seeds one conversation and opens
            // it, so the same chat can be captured from both participants' phones.
            .task {
                guard let side = ChatScreenshotSeed.requestedSide, !activeAddress.isEmpty else { return }
                try? await Task.sleep(for: .seconds(1))
                if let c = ChatScreenshotSeed.seed(side: side, ownerAddress: activeAddress, context: context) {
                    engine?.sync(contacts: contacts)
                    selected = c
                }
            }
            #endif
            #if DEBUG
            // Screenshot helper: -orbitOpenPaywall auto-opens the subscription sheet.
            .task {
                if CommandLine.arguments.contains("-orbitOpenPaywall") {
                    try? await Task.sleep(for: .milliseconds(600))
                    showPaywall = true
                }
            }
            // Screenshot helper: -orbitOpenChat auto-opens a seeded conversation.
            .task {
                guard CommandLine.arguments.contains("-orbitOpenChat") else { return }
                try? await Task.sleep(for: .milliseconds(700))
                // The fullest conversation reads best in a screenshot.
                if let c = contacts.filter({ !$0.isSelf })
                    .max(by: { $0.messages.count < $1.messages.count }) {
                    jumpMessageID = nil
                    selected = c
                }
            }
            #endif
            // Keyed on message counts, not just the contact set: `contacts.map(\.id)`
            // never changes when a message lands, so the sphere was blind to
            // arrivals — no badge, no membership change, nothing.
            .onChange(of: contacts.map { "\($0.id)#\($0.messages.count)#\($0.unreadCount)" }) { _, _ in
                engine?.sync(contacts: contacts)
            }
            .onChange(of: reduceMotion) { _, r in engine = nil; boot(reduced: r) }
            // fullScreenCover, not navigationDestination: opening from search tears
            // down the search overlay and resigns the keyboard (@FocusState) in the
            // same tick, which made a navigationDestination push get dropped — the
            // search closed but no chat opened. A cover presents purely on `item`
            // becoming non-nil, independent of NavigationStack timing.
            .fullScreenCover(item: $selected) { c in
                ChatDetailView(contact: c, jumpToMessageID: jumpMessageID).preferredColorScheme(.dark)
            }
            // Sheets don't inherit the scene's colour scheme, so a black surface
            // was throwing up white sheets. Pin them dark to match.
            .sheet(isPresented: $showAdd) { AddContactView().preferredColorScheme(.dark) }
            // An invite link opens the add-contact sheet with the card already in it.
            .onChange(of: invites.pendingPayload) { _, payload in
                if payload != nil { showAdd = true }
            }
            .onAppear { if invites.pendingPayload != nil { showAdd = true } }
            .sheet(isPresented: $showProfile) { ProfileTabView().preferredColorScheme(.dark) }  // settings live here
            .sheet(item: $profileContact) { c in ContactProfileView(contact: c).preferredColorScheme(.dark) }
            // Swipe-left-to-delete a chat, confirmed (it's unrecoverable — the
            // ratchet session + message history exist only on this device, so
            // there's nothing to restore from). Cancelling springs the row back.
            .confirmationDialog(
                Text("Удалить чат с \(deleteCandidate?.primaryName ?? "")?"),
                isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                titleVisibility: .visible
            ) {
                Button("Удалить чат", role: .destructive) {
                    if let c = deleteCandidate { beginDelete(c) }
                    deleteCandidate = nil
                }
                Button("Отмена", role: .cancel) {
                    deleteCandidate = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { rowSwipeDx = 0 }
                }
            } message: {
                Text("Сообщения удалятся только у тебя. Собеседник ничего не заметит.")
            }
            .sheet(isPresented: $showPaywall) {
                #if DEBUG
                QuotaPaywallSheet(sampleMode: CommandLine.arguments.contains("-paywallSample"))
                    .preferredColorScheme(.dark)
                #else
                QuotaPaywallSheet().preferredColorScheme(.dark)
                #endif
            }
            .sheet(isPresented: $showCirclePicker) {
                circlePicker.preferredColorScheme(.dark).presentationDetents([.medium, .large])
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: boot
    private func boot(reduced: Bool) {
        guard engine == nil else { return }
        let e = OrbitEngine(reduced: reduced)
        e.sync(contacts: contacts)
        #if DEBUG
        // -orbitStartPage N boots straight onto that globe (0 auto, 1 circle),
        // so the curated globe can be inspected without driving the page dots.
        if let i = CommandLine.arguments.firstIndex(of: "-orbitStartPage"),
           i + 1 < CommandLine.arguments.count, let p = Int(CommandLine.arguments[i + 1]) {
            e.goToPage(p)
        }
        if CommandLine.arguments.contains("-orbitStartTimeline") { e.toTimeline() }
        #endif
        engine = e
    }

    // MARK: background
    // Black ground plus one soft grey bloom sitting where the globe does. Glass
    // needs a light source behind it or the frost has nothing to pick up — and
    // it gives the sphere a ground to sit against. Kept far too dim to read as
    // decoration.
    private var background: some View {
        ZStack {
            Orbit.bg0
            RadialGradient(colors: [Orbit.bg1, Orbit.bg0.opacity(0)],
                           center: .center, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: node mesh texture
    // A tiny mesh-network pattern drawn inside each globe node, seeded by its
    // initial so it matches the default MeshAvatar. Unit coords centred on 0,
    // radius ≲0.86; cached per initial so it's built once, not per frame.
    private struct NodeMesh { let pts: [CGPoint]; let edges: [(Int, Int)]; let focal: Int }
    private static var nodeMeshCache: [String: NodeMesh] = [:]
    private static func nodeMesh(seed: String) -> NodeMesh {
        if let m = nodeMeshCache[seed] { return m }
        func hash(_ s: String) -> UInt32 {
            var h: Int32 = 0
            for c in s.unicodeScalars { h = 31 &* h &+ Int32(truncatingIfNeeded: c.value) }
            return UInt32(bitPattern: h)
        }
        func rnd(_ s: UInt32, _ i: UInt32) -> Double {
            Double(s &* 1664525 &+ i &* 1013904223 &+ 12345) / Double(UInt32.max)
        }
        let sd = hash(seed.isEmpty ? "?" : seed), count = 8
        var pts: [CGPoint] = [], depth: [Double] = []
        for i in 0..<count {
            let a = rnd(sd, UInt32(i*3+1)) * 2 * .pi
            let r = 0.28 + 0.58 * rnd(sd, UInt32(i*3+2))
            pts.append(CGPoint(x: cos(a)*r, y: sin(a)*r))
            depth.append(rnd(sd, UInt32(i*3+3)))
        }
        var seen = Set<Int>(); var edges: [(Int, Int)] = []
        for i in 0..<count {
            let near = (0..<count).filter { $0 != i }
                .sorted { hypot(pts[i].x-pts[$0].x, pts[i].y-pts[$0].y)
                        < hypot(pts[i].x-pts[$1].x, pts[i].y-pts[$1].y) }
                .prefix(2)
            for j in near {
                let lo = min(i,j), hi = max(i,j), k = lo*100+hi
                if seen.insert(k).inserted { edges.append((lo, hi)) }
            }
        }
        let focal = depth.indices.max { depth[$0] < depth[$1] } ?? 0
        let m = NodeMesh(pts: pts, edges: edges, focal: focal)
        nodeMeshCache[seed] = m
        return m
    }

    // MARK: the canvas scene
    private func scene(_ engine: OrbitEngine, size: CGSize) -> some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                engine.step(date: tl.date, size: sz)
                let breath = engine.breath(tl.date)
                draw(ctx: ctx, size: sz, engine: engine, breath: breath)
            }
        }
    }

    /// Which nodes may show a name. Walk the globe front-to-back and claim
    /// screen rects greedily: the nearest node wins a contested spot and the one
    /// behind it stays silent. Without this, labels of neighbouring nodes simply
    /// overprinted each other ("Артём"/"Лина") and read as one smear.
    private func labelledNodes(_ engine: OrbitEngine, breath: Double) -> Set<String> {
        var claimed: [CGRect] = []
        var allowed = Set<String>()
        for n in engine.nodes.sorted(by: { $0.depth > $1.depth }) {
            guard n.onSphere, n.rowAlpha < 0.5, n.fade < 0.5 else { continue }
            // Frequent contacts keep their name further round the horizon.
            guard n.depth > 0.62 - n.freq*0.28 else { continue }
            let w = Double(n.name.count) * 6.6 + 8
            let rect = CGRect(x: n.px - w/2, y: n.py + n.size + 5, width: w, height: 15)
            if claimed.contains(where: { $0.intersects(rect) }) { continue }
            claimed.append(rect)
            allowed.insert(n.contactID)
        }
        return allowed
    }

    private func draw(ctx: GraphicsContext, size: CGSize, engine: OrbitEngine, breath: Double) {
        let W = Double(size.width)
        let labelled = labelledNodes(engine, breath: breath)

        // Mesh links first, so nodes sit on top of them. These are what make the
        // globe read as a volume instead of a scatter of dots: the far side of
        // the sphere is the same wireframe, just dimmer.
        // ONE depth-sorted pass over links AND nodes together. Links used to be
        // painted as a block before every node, which meant a bright link between
        // two NEAR contacts was overprinted by whatever FAR node happened to lie
        // across it — the far thing sitting on top of the near thing. A painter's
        // algorithm only works if everything is in the same queue.
        enum Piece { case link(OrbitNode, OrbitNode), node(OrbitNode) }
        var queue: [(depth: Double, piece: Piece)] = []
        queue.reserveCapacity(engine.links.count + engine.nodes.count)
        for l in engine.links {
            guard l.a < engine.nodes.count, l.b < engine.nodes.count else { continue }
            let a = engine.nodes[l.a], b = engine.nodes[l.b]
            // A link sorts by its NEAR end: that is the part of it that can
            // legitimately cover something, and it is what the eye tracks.
            queue.append((max(a.depth, b.depth), .link(a, b)))
        }
        for n in engine.nodes { queue.append((n.depth, .node(n))) }
        queue.sort { $0.depth < $1.depth }               // back → front

        let floor = engine.farFloor
        for (_, piece) in queue {
            guard case var .node(n) = piece else {
                if case let .link(a, b) = piece { drawLink(ctx, a, b, breath: breath) }
                continue
            }
            // Swipe-to-delete: slide this row's avatar+text with the finger, and
            // reveal a red "Delete" plate behind it. Only the row being dragged
            // moves — everything else (badges, links, the rest of the list) stays
            // put. Drawn BEFORE the shift so the plate sits at the row's true,
            // unshifted position (it's what the slide reveals).
            let isSwipingThisRow = engine.mode == .timeline && dragFromRow?.contactID == n.contactID
                && rowSwipeDx < -1
            if isSwipingThisRow {
                let reveal = min(1, -rowSwipeDx / Self.deleteSwipeThreshold)
                let deleteRowH = 68.0   // mirrors OrbitEngine.rowH's row height
                let rowRect = CGRect(x: 16, y: n.py - deleteRowH/2, width: W - 32, height: deleteRowH)
                ctx.fill(Path(roundedRect: rowRect, cornerRadius: 14),
                         with: .color(Theme.negative.opacity(0.85 * reveal)))
                let trash = ctx.resolve(Text(Image(systemName: "trash.fill"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Orbit.ink.opacity(reveal)))
                ctx.draw(trash, at: CGPoint(x: W - 16 - 22, y: n.py))
            }
            if engine.mode == .timeline, dragFromRow?.contactID == n.contactID {
                n.px += rowSwipeDx
            }
            // Delete slide-out: the confirmed row eases fully off the left edge, then
            // gets removed once it's gone (see beginDelete). Purely visual — the
            // contact still exists until the timer fires.
            if n.contactID == deletingID, let since = deletingSince {
                let t = min(1, max(0, engine.now.timeIntervalSince(since)) / Self.deleteAnimDur)
                let e = t * t   // ease-in: starts gentle, accelerates off-screen
                n.px += deleteStartDx + (-(W + 140) - deleteStartDx) * e
            }
            // Opacity carries depth on its own (size stopped doing it), so it has
            // to swing hard or the globe reads flat. The floor tightens as the
            // globe fills: on a busy sphere the far side is mostly what you
            // mistake for the near one, so it gets out of the way.
            let rowness = clampd((n.rowAlpha - 0.55)/0.45, 0, 1)
            // A list-only contact is invisible until its row exists.
            let member = n.onSphere ? 1.0 : rowness
            // ONE depth curve for everything attached to this node — disc, ring,
            // badge. Anything that opts out of it lies about where the node is.
            let depthA = (floor + (1 - floor)*n.depth) * breath * member
            let a = depthA * (1 - n.fade)
            if a <= 0.01 { continue }
            let p = CGPoint(x: n.px, y: n.py)

            // active now → hairline white ring (a stroke, so it never competes
            // with the unread fill); fades out in the timeline
            // Ring = pinned by hand, and nothing else. It is a statement you made
            // about a person, not an inference the app drew about you — so it
            // never appears on its own, and its weight is fixed: there are no
            // degrees of "I chose this one".
            //
            // Frequency still shapes the globe, but through gravity (the people
            // you talk to drift to the front pole) — not through this mark.
            if n.isFavourite {
                let ra = (1 - n.rowAlpha) * depthA * (1 - n.fade)
                if ra > 0.02 {
                    let r = n.size + 5
                    ctx.stroke(Path(ellipseIn: CGRect(x: n.px-r, y: n.py-r, width: r*2, height: r*2)),
                               with: .color(Orbit.label.opacity(0.75*ra)),
                               lineWidth: 2.0)
                }
            }
            // The control spoke: a dashed outline, not a filled avatar — clearly
            // an action, not a person. Its glyph follows the node's initials, so
            // it reads "+" while there's room and "−" once the circle is full.
            if n.contactID == OrbitEngine.addNodeID {
                let ring = Path(ellipseIn: CGRect(x: n.px-n.size, y: n.py-n.size, width: n.size*2, height: n.size*2))
                ctx.stroke(ring, with: .color(Orbit.label.opacity(a*0.5)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                let glyph = ctx.resolve(Text(n.initials)
                    .font(.system(size: n.size*1.1, weight: .regular))
                    .foregroundColor(Orbit.label.opacity(a*0.8)))
                ctx.draw(glyph, at: p)
            } else {
                // Avatar disc in the brand's language: tone fill (carries depth),
                // a faint white mesh texture seeded by the initial, then the letter
                // — the same look as the default MeshAvatar, drawn inline.
                ctx.fill(Path(ellipseIn: CGRect(x: n.px-n.size, y: n.py-n.size, width: n.size*2, height: n.size*2)),
                         with: .color(n.tone.opacity(a)))
                let mesh = Self.nodeMesh(seed: n.initials)
                var mp = Path()
                for (i, j) in mesh.edges {
                    mp.move(to: CGPoint(x: p.x + mesh.pts[i].x*n.size, y: p.y + mesh.pts[i].y*n.size))
                    mp.addLine(to: CGPoint(x: p.x + mesh.pts[j].x*n.size, y: p.y + mesh.pts[j].y*n.size))
                }
                ctx.stroke(mp, with: .color(.white.opacity(a*0.16)), lineWidth: max(0.5, n.size*0.03))
                for (k, pt) in mesh.pts.enumerated() {
                    let rr = n.size * (k == mesh.focal ? 0.09 : 0.055)
                    let op = a * (k == mesh.focal ? 0.55 : 0.30)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x + pt.x*n.size - rr, y: p.y + pt.y*n.size - rr,
                                                    width: rr*2, height: rr*2)),
                             with: .color(.white.opacity(op)))
                }
                let init_ = ctx.resolve(Text(n.initials)
                    .font(.system(size: n.size*0.92, weight: .semibold))
                    .foregroundColor(Orbit.label.opacity(a*0.95)))
                ctx.draw(init_, at: p)
            }

            // sphere node = avatar + name; the label hands off to the row text
            // during the morph, and back nodes stay quiet so the globe reads clean.
            let sf = engine.searchAmount
            let sphereA = (1 - rowness) * (1 - n.fade) * (1 - sf)
            // Depth gate + horizon persistence now live in labelledNodes(), which
            // also resolves collisions between neighbouring labels.
            if sphereA > 0.04, labelled.contains(n.contactID) {
                let na = sphereA * (0.15 + 0.85*n.depth) * breath
                let label = ctx.resolve(Text(n.name)
                    .font(.system(size: 12, weight: .medium))   // caption
                    .foregroundColor(Orbit.label.opacity(na*0.9)))
                ctx.draw(label, at: CGPoint(x: n.px, y: n.py + n.size + 7), anchor: .top)
            }

            // Search results always name themselves. The depth gate above hid
            // most matches, leaving unlabelled discs you couldn't identify. If
            // the hit came from a message rather than the name, show that line
            // too — otherwise a match on "да" inside "Да, помню" is unexplained.
            if sf > 0.05, n.fade < 0.5, engine.matches(n) {
                let name = ctx.resolve(Text(n.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Orbit.label.opacity(sf)))
                ctx.draw(name, at: CGPoint(x: n.px, y: n.py + n.size + 7), anchor: .top)
                // Only when the solved column actually reserved room for it.
                if engine.searchShowFragment, let frag = engine.matchFragment(n) {
                    let f = ctx.resolve(Text(clipText(frag, 32))
                        .font(.system(size: 12))
                        .foregroundColor(Orbit.label2.opacity(sf)))
                    ctx.draw(f, at: CGPoint(x: n.px, y: n.py + n.size + 7 + 20), anchor: .top)
                }
            }

            // timeline row content
            if rowness > 0.01, n.contactID == OrbitEngine.addNodeID {
                // The "+" spoke as a list cell: a single action label, vertically
                // centred, with NO message preview or timestamp — it isn't a chat,
                // so it has no "last message" and no time (which otherwise rendered
                // as a nonsensical "739822 d" from the sentinel's zero date).
                let ta = rowness
                let lx = n.px + n.size + 16
                let label = ctx.resolve(Text(n.name)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Orbit.label.opacity(ta * 0.9)))
                ctx.draw(label, at: CGPoint(x: lx, y: n.py), anchor: .leading)
            } else if rowness > 0.01 {
                let ta = rowness
                let lx = n.px + n.size + 16
                // Apple list-cell hierarchy: 17 semibold title, 15 secondary
                // body, 15 secondary timestamp. Unread lifts the title's weight,
                // not its colour.
                let name = ctx.resolve(Text(n.name)
                    .font(.system(size: 17, weight: n.unread > 0 ? .semibold : .regular))
                    .foregroundColor(Orbit.label.opacity(ta)))
                ctx.draw(name, at: CGPoint(x: lx, y: n.py - 20), anchor: .topLeading)
                // Your private note, to the right of the name — dim, so it reads as
                // a margin annotation, not part of their identity. Sits between the
                // name and the timestamp; clipped so a long note can't collide.
                if !n.note.isEmpty {
                    let nameW = name.measure(in: CGSize(width: W, height: 40)).width
                    let noteX = lx + nameW + 8
                    let avail = (W - 22 - 56) - noteX      // keep clear of the timestamp
                    if avail > 30 {
                        let note = ctx.resolve(Text(clipText(n.note, max(6, Int(avail/7.5))))
                            .font(.system(size: 13))
                            .foregroundColor(Orbit.label3.opacity(ta*0.9)))
                        ctx.draw(note, at: CGPoint(x: noteX, y: n.py - 17), anchor: .topLeading)
                    }
                }
                let msg = ctx.resolve(Text(n.lastText.isEmpty ? " " : n.lastText)
                    .font(.system(size: 15))
                    .foregroundColor(Orbit.label2.opacity(ta)))
                ctx.draw(msg, at: CGPoint(x: lx, y: n.py + 2), anchor: .topLeading)
                let time = ctx.resolve(Text(relTime(n.lastTime))
                    .font(.system(size: 15))
                    .foregroundColor(Orbit.label3.opacity(ta)))
                ctx.draw(time, at: CGPoint(x: W - 22, y: n.py - 20), anchor: .topTrailing)
            }

            // Unread count — the only unread signal now, so it must never blink
            // out mid-morph: the sphere badge fades out exactly as the row badge
            // fades in.
            // Arrival flourish: an expanding, fading ring the moment a message
            // lands, plus a spring "pop" on the unread badge. Purely a welcome —
            // it decays to nothing within ~1.2s and never repeats.
            var badgePop = 1.0
            if let at = engine.arrivalAt[n.contactID] {
                let age = engine.now.timeIntervalSince(at)
                if age >= 0, age < 1.2 {
                    let t = age/1.2
                    let rr = n.size * (1 + 1.6*t)
                    let ringA = (1 - t) * 0.55 * (1 - rowness) * (1 - n.fade)
                    if ringA > 0.01 {
                        ctx.stroke(Path(ellipseIn: CGRect(x: n.px - rr, y: n.py - rr, width: rr*2, height: rr*2)),
                                   with: .color(.white.opacity(ringA)), lineWidth: 1.5)
                    }
                }
                if age >= 0, age < 0.45 { badgePop = 1 + 0.45 * sin(age/0.45 * .pi) }
            }

            if n.unread > 0 {
                // The bubble's SIZE is how fresh the message is — a big bubble
                // means they just wrote, a small one means it has been sitting.
                //
                // Size deliberately does NOT also encode depth: two signals in
                // one channel is the exact bug that made far nodes read as near.
                // Depth stays in the badge's OPACITY (below), which is what
                // stops a distant bubble from shouting over a close one.
                drawBadge(ctx, x: n.px + n.size*0.78, y: n.py - n.size*0.78, count: n.unread,
                          alpha: (1 - rowness) * depthA * (1 - n.fade),
                          scale: lerp(0.45, 1.35, n.freshness) * badgePop)
                drawBadge(ctx, x: W - 32, y: n.py + 14, count: n.unread, alpha: rowness)
            }
        }
    }

    /// Unread count — a white capsule with black numerals. The only filled white
    /// element in the scene, so it reads as "there is something for you" with no
    /// colour doing the work.
    /// One mesh link, shaded per END by that end's own depth so it visibly dives
    /// away rather than running at one flat brightness.
    private func drawLink(_ ctx: GraphicsContext, _ a: OrbitNode, _ b: OrbitNode, breath: Double) {
        // A link only means something on the sphere — drop it as rows form, and
        // drop it for nodes the search has pushed away.
        let vis = (1 - max(a.rowAlpha, b.rowAlpha)) * (1 - max(a.fade, b.fade))
        guard vis > 0.02 else { return }
        // Squared falloff: the near side pops instead of trailing off evenly.
        func endAlpha(_ d: Double) -> Double { 0.44 * (0.03 + 0.97*d*d) * vis * breath }
        let aA = endAlpha(a.depth), bA = endAlpha(b.depth)
        guard max(aA, bA) > 0.012 else { return }
        let pa = CGPoint(x: a.px, y: a.py), pb = CGPoint(x: b.px, y: b.py)
        var path = Path()
        path.move(to: pa)
        path.addLine(to: pb)
        let d = (a.depth + b.depth) / 2
        ctx.stroke(path,
                   with: .linearGradient(
                    Gradient(colors: [Orbit.label.opacity(aA), Orbit.label.opacity(bA)]),
                    startPoint: pa, endPoint: pb),
                   lineWidth: 0.35 + 1.15*d*d)
    }

    /// `scale` shrinks the badge with distance, exactly like the node it belongs
    /// to. A fixed-size badge on a far node ends up LARGER than the node itself.
    private func drawBadge(_ ctx: GraphicsContext, x: Double, y: Double, count: Int,
                           alpha: Double, scale: Double = 1) {
        guard alpha > 0.02 else { return }
        let s = count > 99 ? "99+" : "\(count)"
        let h = 20.0 * scale
        let w = max(h, (Double(s.count) * 9.0 + 12.0) * scale)
        let rect = CGRect(x: x - w/2, y: y - h/2, width: w, height: h)
        ctx.fill(Path(roundedRect: rect, cornerRadius: h/2), with: .color(Orbit.label.opacity(alpha)))
        let t = ctx.resolve(Text(s)
            .font(.system(size: 13*scale, weight: .semibold).monospacedDigit())
            .foregroundColor(Orbit.ink.opacity(alpha)))
        ctx.draw(t, at: CGPoint(x: x, y: y))
    }

    // MARK: circle picker
    // The "+" spoke on the curated globe opens THIS — a chooser of contacts you
    // already have, to add to your circle. Not the new-contact search: the circle
    // is built from people you're already talking to.
    private var circlePicker: some View {
        let people = contacts.filter { !$0.isSelf }
            .sorted { $0.inCircle && !$1.inCircle }   // in-circle first
        return NavigationStack {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(people) { c in
                        let canAdd = Contact.canCircle(c, among: contacts)
                        Button {
                            // Full circle answers the tap with the reason; a row
                            // that silently ignores touches reads as broken.
                            guard c.inCircle || canAdd else {
                                toast.show(String(localized: "В круге уже \(Contact.maxCircle) контактов"))
                                return
                            }
                            c.inCircle.toggle()
                            try? context.save()
                            engine?.sync(contacts: contacts)
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        } label: {
                            HStack(spacing: 12) {
                                MeshAvatarView(id: c.id, name: c.primaryName, size: 40).grayscale(1)
                                Text(c.primaryName)
                                    .font(.system(size: 16)).foregroundStyle(Orbit.label)
                                Spacer()
                                Image(systemName: c.inCircle ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(c.inCircle ? Orbit.label
                                                     : canAdd ? Orbit.label3 : Orbit.label3.opacity(0.4))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
            .background(Color.black)
            .navigationTitle("Добавить в круг")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showCirclePicker = false }.foregroundStyle(Orbit.label)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("В круге \(contacts.filter(\.inCircle).count) из \(Contact.maxCircle)")
                    .font(.system(size: 12)).foregroundStyle(Orbit.label2)
                    .frame(maxWidth: .infinity).padding(.vertical, 6).background(Color.black)
            }
        }
    }

    // MARK: page dots
    // Two globes: the automatic one and your curated circle. Dots show which
    // you're on; tapping a dot or swiping across the strip switches. Paging lives
    // here, in its own strip, so it never fights the globe body — where a
    // horizontal drag rotates.
    private func pageDots(_ engine: OrbitEngine) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<OrbitEngine.pageCount, id: \.self) { i in
                // 7pt dot, 32pt tap target — a bare 7pt circle is impossible to hit.
                Circle()
                    .fill(Orbit.label.opacity(i == engine.page ? 0.95 : 0.3))
                    .frame(width: 7, height: 7)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(motion) { engine.goToPage(i) } }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    /// Horizontal swipe along the bottom strip → next / previous globe.
    private func pageSwipe(_ engine: OrbitEngine) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { g in
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                let dx = g.translation.width
                if dx < -40 { withAnimation(motion) { engine.goToPage(engine.page + 1) } }
                else if dx > 40 { withAnimation(motion) { engine.goToPage(engine.page - 1) } }
            }
    }

    // MARK: top bar
    // Leading: your own identity → profile (settings live in there). Trailing:
    // the message balance → paywall, then compose. Everything else about the app
    // is a gesture, so these four are the whole chrome.
    private func topBar(_ engine: OrbitEngine) -> some View {
        HStack(spacing: 10) {
            // Identity block: avatar on the left, brand eyebrow over your
            // nickname on the right. Avatar centres against the two text lines so
            // nothing sits crooked; eyebrow and nickname share one left edge.
            Button { showProfile = true } label: {
                HStack(spacing: 10) {
                    myAvatar
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        .grayscale(1)                   // identity art, kept monochrome
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PrivaMesh")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.4)
                            .foregroundStyle(Orbit.label2)
                        HStack(spacing: 5) {
                            Text(engine.mode == .timeline
                                 ? (engine.page == 1 ? String(localized: "Круг") : String(localized: "Лента"))
                                 : nicknameManager.nickname)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Orbit.label)
                                .lineLimit(1)
                            // Verified tick next to your own nickname when subscribed.
                            // Only in the sphere mode, where the line is your nick —
                            // the timeline shows a page title there, not a name.
                            if engine.mode != .timeline, subscription.isSubscribed {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Orbit.label)
                                    .modifier(ShimmerSweep())   // one gentle sweep on appear
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Профиль и настройки")

            Spacer(minLength: 8)

            // Message balance — metered sending, so the count is real information.
            Button { showPaywall = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Orbit.label2)
                    Text("\(quota.remaining)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Orbit.label)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .orbitGlass(13)
            }
            .buttonStyle(.plain)
            .scaleEffect(quotaBounce)
            .onChange(of: quota.remaining) { _, _ in
                // A soft spring bounce whenever the balance changes (send / top-up).
                quotaBounce = 1.16
                withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { quotaBounce = 1 }
            }
            .accessibilityLabel("Осталось сообщений: \(quota.remaining)")

            Button { showAdd = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Orbit.label)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Новый контакт")
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 58)          // two lines now: brand eyebrow + avatar row
        // In the timeline the list scrolls under the bar, so it earns a frosted
        // edge (Apple's scroll-edge behaviour). The sphere has nothing beneath
        // it — the bar stays plain there.
        .background {
            if engine.mode == .timeline {
                // No material here either. The list scrolls under the title, so
                // instead of frosting it, fade it into black at the bottom — the
                // rows dissolve rather than blur, and the title stays legible.
                LinearGradient(
                    stops: [.init(color: .black, location: 0),
                            .init(color: .black, location: 0.6),
                            .init(color: .black.opacity(0), location: 1)],
                    startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    @ViewBuilder
    private var myAvatar: some View {
        if let seed = avatars.activeDesign?.id {
            NFTAvatarView(seed: seed, size: 30)
        } else {
            MeshAvatarView(id: activeAddress.isEmpty ? "me" : activeAddress,
                           name: nicknameManager.nickname, size: 30)
        }
    }

    // MARK: overlays (frosted glass + thin chrome, above the scene)
    @ViewBuilder
    private func overlays(_ engine: OrbitEngine) -> some View {
        VStack(spacing: 0) {
            // The bar carries the controls, so it must stay hit-testable.
            topBar(engine)
                .opacity(engine.mode == .search ? 0 : 1)
                .allowsHitTesting(engine.mode != .search)

            // A plain search bar pinned to the top of the chats feed, the way a
            // list search sits everywhere else. Tapping it opens the search focus
            // (same field, same message+nickname search, same tap-to-jump).
            if engine.mode == .timeline {
                let show = engine.atListTop || engine.timelineSearching
                timelineSearchBar(engine)
                    .opacity(show ? 1 : 0)
                    .offset(y: show ? 0 : -56)
                    .allowsHitTesting(show)
                    .animation(.easeOut(duration: 0.2), value: show)
            }

            // A single chevron under the bar, pointing the way the gesture goes —
            // pull down to open the chats feed. Always present on the resting
            // sphere so the feed is discoverable; it just brightens when there's
            // unread waiting (inboxCueVisible). It sits at the top because that's
            // where the pull starts; a worded pill at the bottom was explaining a
            // gesture from the wrong end of it.
            if engine.mode != .search, engine.pullHintVisible {
                Image(systemName: "chevron.down")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Orbit.label.opacity(engine.inboxCueVisible ? 1 : 0.4))
                    .offset(y: cueBob ? 3 : -3)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            cueBob = true
                        }
                    }
                    .onDisappear { cueBob = false }
            }

            Spacer()
            if engine.mode == .timeline {
                VStack(spacing: 10) {
                    // Two feeds: page dots make the second one discoverable and let
                    // you jump straight to it (a horizontal swipe on the list pages
                    // too). Tappable, so kept above the non-interactive handle.
                    pageDots(engine)
                        .contentShape(Rectangle())
                        .gesture(pageSwipe(engine))
                    // The handle back to the globe — a grabber, so it reads as a pull.
                    VStack(spacing: 7) {
                        Capsule().fill(Orbit.label.opacity(0.35)).frame(width: 34, height: 4)
                        Text("Потяните вверх — сфера")
                            .font(.system(size: 13)).foregroundStyle(Orbit.label2)
                    }
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
                    .orbitGlass(20)
                    .allowsHitTesting(false)
                }
                .padding(.bottom, 10)
            } else if engine.mode == .sphere {
                // Which globe you're on — page dots, Apple style. Tappable. A
                // horizontal swipe anywhere along the bottom strip pages too,
                // kept off the globe body where a drag means rotate.
                pageDots(engine)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)
                    .contentShape(Rectangle())
                    .gesture(pageSwipe(engine))
            }
        }

        if engine.mode == .search {
            // A tap on empty space dismisses search — you shouldn't have to aim
            // for the little ✕. A tap that lands on a converged match opens that
            // chat instead. The catcher sits UNDER the field so the field's own
            // taps (text, clear button) still reach it.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    if let n = engine.node(at: v.location), let c = contact(for: n.contactID) {
                        open(c, engine)
                    } else {
                        dismissSearch(engine)
                    }
                })
            VStack { searchField(engine); Spacer() }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }

        if let qc = quickContact {
            quickReply(engine, contact: qc)
        }
    }

    private func dismissSearch(_ engine: OrbitEngine) {
        searchText = ""; engine.query = ""; searchFocused = false
        withAnimation(motion) { engine.closeSearch() }
    }

    /// The chat-list search bar, pinned to the top of the timeline. This is a
    /// SEPARATE search from the globe's: it never switches to the sphere — it
    /// filters the list in place (matches pack to the top, everything else drops
    /// away). Tapping a filtered row opens the chat (and jumps to the matched
    /// message when the hit came from message text).
    private func timelineSearchBar(_ engine: OrbitEngine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Orbit.label2)
            TextField("Поиск", text: $timelineText)
                .textFieldStyle(.plain)
                .foregroundStyle(Orbit.label)
                .tint(Orbit.label)
                .focused($timelineFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: timelineText) { _, v in
                    engine.setTimelineQuery(v.trimmingCharacters(in: .whitespaces))
                }
            if !timelineText.isEmpty {
                Button {
                    timelineText = ""
                    engine.endTimelineSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Orbit.label2)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 14).padding(.vertical, 11)
        .orbitGlass(16)
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private func searchField(_ engine: OrbitEngine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(Orbit.label2)
            TextField("Поиск", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Orbit.label)
                .tint(Orbit.label)
                .focused($searchFocused)
                .submitLabel(.search)
                .onChange(of: searchText) { _, v in engine.setQuery(v.trimmingCharacters(in: .whitespaces)) }
                .onSubmit {
                    let m = contacts.filter { !$0.isSelf && engine.matches(node(for: $0, engine)) }
                    if m.count == 1 { open(m[0], engine) }
                }
            Button { dismissSearch(engine) } label: {
                Image(systemName: "xmark").foregroundStyle(Orbit.label2)
            }
                .buttonStyle(.plain)
        }
        .padding(14)
        .orbitGlass(18)
        .padding(.horizontal, 22).padding(.top, 8)
        .onAppear { searchFocused = true }
    }

    private func quickReply(_ engine: OrbitEngine, contact: Contact) -> some View {
        VStack {
            Spacer().frame(height: 120)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    // Name + last message open the full chat. Previously a tap
                    // here hit no handler, fell through to the dismiss scrim, and
                    // simply closed the card — the most obvious thing to press
                    // did the least useful thing.
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(contact.primaryName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Orbit.label2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Orbit.label3)
                        }
                        let uq = quickUnread(contact)
                        if uq.shown.isEmpty {
                            // No unread — just echo the latest line, as before.
                            Text(contact.lastMessage?.body ?? "Нет сообщений")
                                .font(.system(size: 17)).foregroundStyle(Orbit.label)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                // More unread above than the three shown.
                                if uq.hidden > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 9, weight: .semibold))
                                        Text("ещё \(uq.hidden) выше")
                                            .font(.system(size: 12))
                                    }
                                    .foregroundStyle(Orbit.label3)
                                }
                                ForEach(uq.shown, id: \.id) { m in
                                    Text(m.body)
                                        .font(.system(size: 16)).foregroundStyle(Orbit.label)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { openFullChat(contact, engine) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Открыть чат с \(contact.primaryName)")

                    // The manual route onto the globe's inner circle. Kept OUTSIDE
                    // the tappable area above so the two never fight for a touch.
                    // Same cap as the profile screen — enforced through the
                    // model's own rule so the entry points can't drift apart.
                    let canPin = Contact.canPin(contact, among: contacts)
                    Button {
                        guard contact.isFavourite || canPin else {
                            toast.show(String(localized: "Уже выбрано \(Contact.maxFavourites) близких"))
                            return
                        }
                        contact.isFavourite.toggle()
                        try? context.save()
                        engine.sync(contacts: contacts)
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        Image(systemName: contact.isFavourite ? "circle.circle.fill" : "circle.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(contact.isFavourite ? Orbit.label
                                             : canPin ? Orbit.label2 : Orbit.label3)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(contact.isFavourite ? "Убрать из близких"
                                        : canPin ? "Добавить в близкие"
                                        : "Уже выбрано \(Contact.maxFavourites) близких")
                }
                HStack(spacing: 10) {
                    TextField("Написать \(dative(contact.primaryName))", text: $quickText)
                        .textFieldStyle(.plain).foregroundStyle(Orbit.label).tint(Orbit.label)
                        .focused($quickFocused)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06)))
                    Button { sendQuick(contact) } label: {
                        Image(systemName: "paperplane.fill").foregroundStyle(Orbit.ink)
                            .frame(width: 40, height: 40).background(Circle().fill(Orbit.label))
                            .opacity(quickText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.3 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(18)
            .orbitGlass(26)
            .padding(.horizontal, 22)
            Spacer()
        }
        .background(
            Color.black.opacity(0.001)
                .onTapGesture { closeQuick() }
        )
        // The SCALED view must span the screen: a scale anchor is expressed in
        // the view's own bounds, and quickAnchor is normalised to the canvas.
        // Scaling just the card would aim the anchor at the wrong place entirely.
        .ignoresSafeArea()
        .scaleEffect(quickVisible ? 1 : (reduceMotion ? 1 : 0.04), anchor: quickAnchor)
        .opacity(quickVisible ? 1 : 0)
        .onAppear { quickFocused = true }
    }

    // MARK: gestures
    private func sceneDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard let engine, engine.mode != .search, quickContact == nil else { return }
                if dragStart == nil {
                    dragStart = g.startLocation; dragLast = g.startLocation
                    dragMoved = 0; dragDx = 0; dragDy = 0; lpFired = false; sawPinch = false
                    dragFromHandle = engine.mode == .timeline
                        && Double(g.startLocation.y) > Double(size.height) - Self.handleZone
                    dragFromTop = engine.mode == .sphere
                        && Double(g.startLocation.y) < Self.topZone
                    // A horizontal drag starting ON a row deletes that chat, rather
                    // than paging between the two feeds — paging stays available
                    // from anywhere else (handled below by dragFromRow == nil).
                    dragFromRow = engine.mode == .timeline
                        ? engine.node(at: g.startLocation).flatMap { $0.contactID == OrbitEngine.addNodeID ? nil : $0 }
                        : nil
                    rowSwipeDx = 0
                    rowSwipeEngaged = false
                    scheduleLongPress(at: g.startLocation, engine: engine)
                }
                let last = dragLast ?? g.startLocation
                let dx = Double(g.location.x - last.x), dy = Double(g.location.y - last.y)
                dragMoved += hypot(dx, dy); dragDx += dx; dragDy += dy
                dragLast = g.location
                if dragMoved > 8 { cancelLongPress() }
                if lpFired { return }
                // During a pinch the drag gesture also fires — its "location" is the
                // jumping centroid of two fingers, which fed huge deltas into
                // rotate() and sent the globe spinning. Ignore rotation while
                // pinching, and remember it so onEnded doesn't read it as a swipe.
                if isPinching { sawPinch = true; cancelLongPress(); return }
                // A pull that began in the top strip is opening the chat list, not
                // turning the globe — don't spin it while the user pulls down.
                // Swiping a chat row left reveals a delete affordance — it takes
                // over the gesture entirely (no rotate/scroll/page while it's live).
                if let row = dragFromRow, contact(for: row.contactID)?.isSelf != true {
                    // Commit to the swipe only when the drag is clearly horizontal.
                    // A vertical intent releases the row so the list scrolls; a tap
                    // (no dominant axis) leaves it un-engaged so onEnded opens the chat.
                    if !rowSwipeEngaged {
                        if abs(dragDx) > 8, abs(dragDx) > abs(dragDy) * 1.4 {
                            rowSwipeEngaged = true
                        } else if abs(dragDy) > 8 {
                            dragFromRow = nil          // it's a scroll — let it through
                        }
                    }
                    if rowSwipeEngaged {
                        rowSwipeDx = min(0, max(-140, rowSwipeDx + dx))
                        return
                    }
                    if dragFromRow != nil { return }   // still deciding — hold still
                }
                if engine.mode == .sphere, !dragFromTop { engine.rotate(dx: dx, dy: dy) }
                // A drag off the handle never scrolls — it's pulling the shape,
                // not the content.
                else if engine.mode == .timeline, !dragFromHandle { engine.scrollTimeline(dy: dy) }
            }
            .onEnded { g in
                cancelLongPress()
                let swipedRow = rowSwipeEngaged ? dragFromRow : nil
                defer { dragStart = nil; dragLast = nil; sawPinch = false; dragFromRow = nil; rowSwipeEngaged = false }
                guard let engine, quickContact == nil, !lpFired, !isPinching, !sawPinch,
                      !engine.zoomActive else { return }
                // Resolve the row swipe: past the threshold, delete (with an undo
                // toast, since a chat is unrecoverable — the message history and
                // the shared secret both live only on this device); short of it,
                // spring the row back to rest.
                if let row = swipedRow, contact(for: row.contactID)?.isSelf != true {
                    if rowSwipeDx < -Self.deleteSwipeThreshold, let c = contact(for: row.contactID) {
                        deleteCandidate = c
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { rowSwipeDx = 0 }
                    }
                    return
                }
                // Sum the per-frame deltas ourselves. Neither (location - start)
                // nor g.translation is dependable on the final event of a fast
                // flick — both silently ate swipes — but the incremental deltas
                // are correct (they already drive the rotation).
                let totalDy = dragDy
                let totalDx = dragDx
                let moved = dragMoved
                if abs(totalDy) > 70, abs(totalDy) > abs(totalDx)*1.3 {
                    // The sphere opens the list only when the pull STARTED in the
                    // top strip; the timeline exits only from its bottom handle.
                    // Everywhere else a vertical drag rotates, so spinning the globe
                    // never accidentally throws you into the chats.
                    if totalDy > 0, engine.mode == .sphere, dragFromTop {
                        withAnimation(motion) { engine.toTimeline() }; return
                    }
                    if totalDy < 0, engine.mode == .timeline, dragFromHandle {
                        withAnimation(motion) { engine.toSphere() }; return
                    }
                }
                // In the timeline, a horizontal swipe crosses between the two
                // feeds — the recency globe (page 0) and the curated circle
                // (page 1) — so you can reach the circle's chats straight from the
                // list, without going back out to the sphere first.
                if engine.mode == .timeline,
                   abs(totalDx) > 60, abs(totalDx) > abs(totalDy)*1.3 {
                    let next = engine.page + (totalDx < 0 ? 1 : -1)
                    if next >= 0, next < OrbitEngine.pageCount {
                        engine.tlScroll = 0; engine.tlScrollV = 0
                        withAnimation(motion) { engine.goToPage(next) }
                    }
                    return
                }
                if moved < 10, hypot(totalDx, totalDy) < 10 {   // a tap
                    if let n = engine.node(at: g.location) {
                        if n.contactID == OrbitEngine.addNodeID {
                            // Same sentinel, two meanings by globe: the automatic
                            // globe's cold-start "+" makes a NEW contact; the
                            // curated globe's "+" pulls from existing ones.
                            if engine.page == 0 { showAdd = true }
                            else { showCirclePicker = true }
                        } else if let c = contact(for: n.contactID) {
                            open(c, engine)
                        }
                    } else if engine.mode == .sphere {
                        withAnimation(motion) { engine.openSearch() }
                    }
                }
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                // Zoom only on the automatic globe. The curated circle is a fixed
                // ring — no zoom, no spin.
                guard let engine, engine.page == 0 else { return }
                isPinching = true
                engine.velX = 0; engine.velY = 0        // no leftover spin under the pinch
                engine.zoom(by: (1 - v.magnification) * 0.02)
            }
            .onEnded { _ in isPinching = false }
    }

    private func scheduleLongPress(at p: CGPoint, engine: OrbitEngine) {
        // Long-press means different things per surface. In the timeline it's a
        // shortcut into the contact's profile/settings; the quick-reply card is
        // the globe's alone. A plain tap in either place still opens the chat.
        guard engine.mode == .sphere || engine.mode == .timeline else { return }
        if engine.mode == .timeline {
            let work = DispatchWorkItem {
                guard dragMoved < 8, let n = engine.node(at: p),
                      let c = contact(for: n.contactID), !c.isSelf else { return }
                lpFired = true
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                profileContact = c
            }
            lpWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.43, execute: work)
            return
        }
        let work = DispatchWorkItem {
            guard dragMoved < 8, let n = engine.node(at: p), let c = contact(for: n.contactID) else { return }
            lpFired = true
            engine.velX = 0; engine.velY = 0
            // Anchor the card's growth on the node itself, in normalised screen
            // coordinates — that's what ties the card to the face you pressed.
            let sz = engine.size
            if sz.width > 0, sz.height > 0 {
                quickAnchor = UnitPoint(x: n.px / Double(sz.width), y: n.py / Double(sz.height))
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            // Mount it collapsed at the node, then let the spring pull it open.
            quickContact = c
            quickVisible = false
            DispatchQueue.main.async { withAnimation(motion) { quickVisible = true } }
        }
        lpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.43, execute: work)
    }
    private func cancelLongPress() { lpWork?.cancel(); lpWork = nil }

    // MARK: actions
    private func node(for c: Contact, _ engine: OrbitEngine) -> OrbitNode {
        engine.nodes.first { $0.contactID == c.id }
            ?? OrbitNode(contactID: c.id, name: c.primaryName, initials: "", tone: .gray,
                         unread: 0, freshness: 0, lastText: "", lastTime: c.createdAt,
                         lastIncoming: false, freq: 0, isFavourite: c.isFavourite, row: 0)
    }
    private func contact(for id: String) -> Contact? { contacts.first { $0.id == id } }

    private func open(_ c: Contact, _ engine: OrbitEngine) {
        markRead(c)
        if engine.mode == .search {
            // Carry the searched message (if the hit came from message text) so the
            // chat scrolls to it. Set BEFORE `selected`, which builds the chat.
            jumpMessageID = engine.matchedMessageID(for: c.id)
            // Push the chat FIRST, in this same tick. Tearing down search — mode
            // change + resigning the keyboard (@FocusState) — in the SAME tick as
            // the navigation makes SwiftUI drop the push (search just closed, no
            // chat). So defer the teardown one runloop; the pushed chat covers it.
            selected = c
            DispatchQueue.main.async {
                engine.closeSearch(); searchText = ""; searchFocused = false
            }
            return
        }
        // Timeline (incl. chat-list search) or sphere: jump to the matched message
        // when there's an active query, else open at the bottom as usual.
        jumpMessageID = engine.matchedMessageID(for: c.id)
        selected = c
    }
    private func markRead(_ c: Contact) {
        var changed = false
        for m in c.messages where !m.isOutgoing && !m.isRead { m.isRead = true; changed = true }
        if changed { try? context.save(); engine?.sync(contacts: contacts) }
    }
    /// Delete a chat LOCALLY ONLY — this device's copy of the contact and its
    /// entire message history. There is no server to delete anything on, and
    /// nothing is sent to the other side: they keep their own copy and notice
    /// nothing. Re-adding the same person later starts a fresh session (their
    /// stealth chain has moved on regardless).
    private func deleteChat(_ c: Contact) {
        guard !c.isSelf else { return }   // Saved Messages is not swipe-deletable
        context.delete(c)                 // cascades to c.messages
        try? context.save()
        engine?.sync(contacts: contacts)
    }
    /// Play the row's slide-out, then actually delete once it's off-screen so the
    /// list can close the gap. The slide is driven per-frame in the Canvas from
    /// `deletingSince` (the Canvas already redraws every frame via TimelineView).
    private func beginDelete(_ c: Contact) {
        deleteStartDx = rowSwipeDx        // continue from where the finger let go
        rowSwipeDx = 0
        deletingID = c.id
        deletingSince = engine?.now ?? Date()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deleteAnimDur) {
            deleteChat(c)
            deletingID = nil
            deletingSince = nil
            deleteStartDx = 0
        }
    }
    /// The unread incoming messages to preview in the quick-reply card: the three
    /// most recent, plus how many older unread ones sit above them (not shown).
    private func quickUnread(_ c: Contact) -> (shown: [ChatMessage], hidden: Int) {
        let unread = c.messages
            .filter { !$0.isOutgoing && !$0.isRead }
            .sorted { $0.sentAt < $1.sentAt }
        let shown = Array(unread.suffix(3))
        return (shown, unread.count - shown.count)
    }

    private func sendQuick(_ c: Contact) {
        let t = quickText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        // Replying clears only the messages you actually saw in the card — the
        // three most recent unread. Any older unread above them stay unread, so
        // the badge drops by what you read, not to zero.
        for m in quickUnread(c).shown { m.isRead = true }
        let msg = ChatMessage(id: UUID().uuidString, body: t, isOutgoing: true, sentAt: Date(), status: "sending")
        msg.contact = c; c.messages.append(msg)
        try? context.save()
        closeQuick(); engine?.sync(contacts: contacts)
    }
    /// Collapses back into the node it came from. The card stays mounted for the
    /// length of the spring — unmounting it up front is exactly what killed the
    /// animation before — and is torn down only once it has arrived.
    /// Quick reply → the whole conversation. Tears the card down outright rather
    /// than playing it back into the node: we're leaving this screen, so a
    /// collapse animation would fight the push and just look like a stutter.
    private func openFullChat(_ c: Contact, _ engine: OrbitEngine) {
        quickFocused = false
        quickVisible = false
        quickContact = nil
        quickText = ""
        open(c, engine)
    }

    private func closeQuick() {
        quickFocused = false
        withAnimation(motion) { quickVisible = false }
        let hold = reduceMotion ? 0.16 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            guard !quickVisible else { return }   // reopened mid-collapse
            quickContact = nil
            quickText = ""
        }
    }
}

// MARK: - Formatting helpers

/// Canvas text doesn't truncate on its own — a long message would run off both
/// edges of the screen.
private func clipText(_ s: String, _ maxChars: Int) -> String {
    s.count <= maxChars ? s : String(s.prefix(maxChars - 1)) + "…"
}

private func relTime(_ d: Date) -> String {
    let s = Date().timeIntervalSince(d)
    // Compact units, localized to the app language (ru: мин/ч/д, en: min/h/d).
    let ru = Locale.current.language.languageCode?.identifier == "ru"
    if s < 3600 { let n = max(1, Int(s/60)); return ru ? "\(n) мин" : "\(n) min" }
    if s < 86400 { let n = Int(s/3600); return ru ? "\(n) ч" : "\(n) h" }
    let n = Int(s/86400); return ru ? "\(n) д" : "\(n) d"
}

// light-touch dative for "Написать <кому>": names ending in -а/-я → -е
private func dative(_ name: String) -> String {
    guard let last = name.last else { return name }
    if last == "а" || last == "я" { return String(name.dropLast()) + "е" }
    return name
}

#Preview {
    OrbitChatsView()
        .environment(WalletManager())
        .environment(MessageQuotaService())
        .environment(AvatarService())
        .environment(NicknameManager())
        .modelContainer(for: [Contact.self, ChatMessage.self], inMemory: true)
}

/// A single soft highlight sweep across a view on appear — used for the verified
/// tick. Masked to the view's own shape, so only the glyph shimmers.
private struct ShimmerSweep: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.95), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 1.6)
                    .offset(x: phase * geo.size.width * 2)
                    .blendMode(.plusLighter)
            }
            .mask(content)
            .allowsHitTesting(false)
        )
        .onAppear {
            phase = -1
            withAnimation(.easeInOut(duration: 1.1).delay(0.35)) { phase = 1 }
        }
    }
}
