import SwiftUI

// A decided plan becomes a Google Drive folder: SerpApi does the research,
// Muse writes it up as Sheets and Docs, and the group shares the folder link.

enum WorkspaceFileKind: String, Hashable {
    case sheet, doc, folder

    var label: String {
        switch self {
        case .sheet: "Google Sheet"
        case .doc: "Google Doc"
        case .folder: "Folder"
        }
    }

    var symbol: String {
        switch self {
        case .sheet: "tablecells.fill"
        case .doc: "doc.text.fill"
        case .folder: "folder.fill"
        }
    }

    var tint: Tint {
        switch self {
        case .sheet: .activities
        case .doc: .flights
        case .folder: .stays
        }
    }
}

enum DocBlock: Hashable {
    case title(String)
    case heading(String)
    case paragraph(String)
    case bullet(String)
}

enum FileContent: Hashable {
    case sheet(columns: [String], rows: [[String]], footer: String?)
    case doc([DocBlock])
    case folder(String)
}

struct WorkspaceFile: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var kind: WorkspaceFileKind
    var summary: String          // "6 rows · totals per person"
    var sources: [String]        // "Google Flights", "Google Hotels"
    var content: FileContent
}

/// One SerpApi request the build makes.
struct ResearchCall: Identifiable, Hashable {
    let id = UUID()
    var engine: String           // "google_flights"
    var query: String
    var result: String           // "14 itineraries"
    var duration: Double
}

/// The finished folder.
struct PlanWorkspace: Hashable {
    var folderName: String
    var url: URL
    var files: [WorkspaceFile]
    var calls: [ResearchCall]
    var builtAt: Date
    var sharedTo: String?        // chat it was shared to
}

/// Everything the builder needs to produce, decided before any calls are made.
struct WorkspaceBlueprint {
    var folderName: String
    var calls: [ResearchCall]
    var files: [WorkspaceFile]
}

extension Mock {
    static func blueprint(for plan: Plan) -> WorkspaceBlueprint {
        plan.kind == .trip ? tripBlueprint : carBlueprint
    }

    // MARK: Trip

    static let tripBlueprint = WorkspaceBlueprint(
        folderName: "Japan Trip 2027",
        calls: [
            ResearchCall(engine: "google_flights", query: "AUS → HND, Mar 26 – Apr 4, 4 adults", result: "14 itineraries", duration: 2.1),
            ResearchCall(engine: "google_hotels", query: "Shinjuku, Mar 26 – 30, 2 rooms", result: "22 properties", duration: 1.8),
            ResearchCall(engine: "google_hotels", query: "Kyoto Higashiyama, Mar 30 – Apr 2", result: "18 properties", duration: 1.6),
            ResearchCall(engine: "google_maps", query: "best ramen and izakaya, Shinjuku", result: "20 places", duration: 1.3),
            ResearchCall(engine: "google_maps", query: "top things to do, Kyoto", result: "20 places", duration: 1.2),
            ResearchCall(engine: "google", query: "Shinkansen Tokyo to Kyoto fare", result: "10 results", duration: 0.9),
            ResearchCall(engine: "google", query: "Japan entry requirements for US citizens", result: "8 results", duration: 0.8),
        ],
        files: [
            WorkspaceFile(
                name: "Budget", kind: .sheet, summary: "7 rows · per person and group totals",
                sources: ["Google Flights", "Google Hotels", "Google Maps"],
                content: .sheet(
                    columns: ["Item", "Per person", "Group of 4", "Source"],
                    rows: [
                        ["Flights · ANA via LAX", "$1,148", "$4,592", "Google Flights"],
                        ["Hotel Gracery · 4 nights", "$336", "$1,344", "Google Hotels"],
                        ["Kyoto Machiya · 3 nights", "$161", "$642", "Google Hotels"],
                        ["Shinkansen round trip", "$95", "$380", "Google Search"],
                        ["Activities", "$140", "$560", "Google Maps"],
                        ["Food · 9 days", "$360", "$1,440", "Google Maps"],
                        ["Total", "$2,240", "$8,958", ""],
                    ],
                    footer: "Under the $2,500 budget by $260 each"
                )
            ),
            WorkspaceFile(
                name: "Itinerary", kind: .doc, summary: "9 days · times, places, bookings",
                sources: ["Google Flights", "Google Maps"],
                content: .doc([
                    .title("Japan Trip 2027"),
                    .paragraph("Mar 26 – Apr 4 · Devin, Sam, Maya, Jordan"),
                    .heading("Day 1 · Thu, Mar 26 · Tokyo"),
                    .bullet("3:40 PM  Land at Haneda, ANA NH 107, Terminal 3"),
                    .bullet("5:30 PM  Check in at Hotel Gracery Shinjuku"),
                    .bullet("8:00 PM  Dinner at Omoide Yokocho"),
                    .heading("Day 2 · Fri, Mar 27 · Tokyo"),
                    .bullet("10:00 AM  teamLab Planets (timed entry)"),
                    .bullet("2:00 PM  Tsukiji Outer Market"),
                    .bullet("6:30 PM  Shibuya Sky at sunset"),
                    .heading("Day 5 · Mon, Mar 30 · Kyoto"),
                    .bullet("9:00 AM  Shinkansen to Kyoto, 2h 15m"),
                    .bullet("1:00 PM  Check in at Kyoto Machiya House"),
                ])
            ),
            WorkspaceFile(
                name: "Flights and stays", kind: .sheet, summary: "Every option the group compared",
                sources: ["Google Flights", "Google Hotels"],
                content: .sheet(
                    columns: ["Option", "Price", "Votes", "Why"],
                    rows: [
                        ["ANA via LAX", "$1,148", "4", "Picked · cheapest sane layover"],
                        ["JAL via DFW", "$1,312", "1", "Fastest, lands at Narita"],
                        ["United via SFO", "$1,089", "0", "Leaves a day late"],
                        ["Hotel Gracery Shinjuku", "$168/night", "4", "Picked · central"],
                        ["Kyoto Machiya House", "$214/night", "4", "Picked · roomy"],
                        ["Ryokan Yachiyo", "$250/night", "0", "Breakfast included"],
                    ],
                    footer: nil
                )
            ),
            WorkspaceFile(
                name: "Food guide", kind: .doc, summary: "12 spots near where you're staying",
                sources: ["Google Maps"],
                content: .doc([
                    .title("Where to eat"),
                    .heading("Near Shinjuku"),
                    .bullet("Ichiran Ramen · 4.3 · open 24 hours, solo booths (Maya's pick)"),
                    .bullet("Omoide Yokocho · yakitori alley, about $25 each"),
                    .bullet("Fuunji · 4.5 · tsukemen, expect a short line"),
                    .heading("Near Gion, Kyoto"),
                    .bullet("Nishiki Market · 4.3 · street food for lunch"),
                    .bullet("Gion Kappa · 4.4 · casual izakaya, reserve for 4"),
                ])
            ),
            WorkspaceFile(
                name: "Before you go", kind: .doc, summary: "Entry rules, money, phones, packing",
                sources: ["Google Search"],
                content: .doc([
                    .title("Before you go"),
                    .bullet("Passports valid for the whole stay. US citizens don't need a visa for short visits."),
                    .bullet("Bring some yen: smaller shops and shrines are often cash only."),
                    .bullet("Get an eSIM or pocket Wi-Fi before landing."),
                    .bullet("Outlets are Type A like the US, so no adapter needed."),
                    .bullet("Book teamLab Planets two weeks ahead."),
                ])
            ),
            WorkspaceFile(
                name: "Bookings", kind: .folder, summary: "Drop confirmations here",
                sources: [], content: .folder("Empty. Forward confirmation emails and they'll be filed here.")
            ),
        ]
    )

    // MARK: Car

    static let carBlueprint = WorkspaceBlueprint(
        folderName: "Our next car",
        calls: [
            ResearchCall(engine: "google_shopping", query: "2023 Toyota RAV4 XLE, ~37k mi, Austin", result: "14 listings", duration: 2.4),
            ResearchCall(engine: "google", query: "2026 Toyota RAV4 lease offers Texas", result: "9 results", duration: 1.5),
            ResearchCall(engine: "google", query: "auto loan rates for a lease buyout", result: "10 results", duration: 1.1),
            ResearchCall(engine: "google_maps", query: "Toyota dealers near Austin", result: "6 places", duration: 1.0),
        ],
        files: [
            WorkspaceFile(
                name: "Cost comparison", kind: .sheet, summary: "4 options · monthly and total",
                sources: ["Google Shopping", "Google Search"],
                content: .sheet(
                    columns: ["Option", "Monthly", "Total", "Votes"],
                    rows: [
                        ["Buy out", "$478", "$28,680", "3"],
                        ["Return and lease new", "$429", "$16,584", "1"],
                        ["Trade in", "$512", "+$3,870 equity", "0"],
                        ["Extend 6 months", "$389", "$2,334", "0"],
                    ],
                    footer: "Simulated account data"
                )
            ),
            WorkspaceFile(
                name: "Market prices", kind: .sheet, summary: "14 similar RAV4s for sale",
                sources: ["Google Shopping"],
                content: .sheet(
                    columns: ["Listing", "Miles", "Price"],
                    rows: [
                        ["2023 RAV4 XLE · Round Rock", "34,100", "$28,900"],
                        ["2023 RAV4 XLE · Austin", "38,750", "$27,495"],
                        ["2023 RAV4 XLE · San Marcos", "36,200", "$28,250"],
                        ["Average of 14", "37,000", "$28,050"],
                    ],
                    footer: "Your buyout price: $24,180"
                )
            ),
            WorkspaceFile(
                name: "Dealer visit prep", kind: .doc, summary: "What to bring and ask",
                sources: ["Google Maps", "Google Search"],
                content: .doc([
                    .title("Dealer visit"),
                    .heading("Bring"),
                    .bullet("Driver's license and proof of insurance"),
                    .bullet("Lease agreement and latest statement"),
                    .heading("Ask"),
                    .bullet("Can you match 5.9% APR for 60 months?"),
                    .bullet("Any fees on top of the $24,180 buyout?"),
                    .bullet("Is a pre-purchase inspection included?"),
                ])
            ),
            WorkspaceFile(
                name: "Decision summary", kind: .doc, summary: "Why buying out wins",
                sources: ["Google Shopping"],
                content: .doc([
                    .title("Our next car: buy out the RAV4"),
                    .paragraph("The buyout price is about $3,900 under what similar RAV4s sell for, and buying out avoids about $1,140 in mileage fees. Three of four of us voted for it."),
                    .paragraph("Simulated account data."),
                ])
            ),
        ]
    )
}
