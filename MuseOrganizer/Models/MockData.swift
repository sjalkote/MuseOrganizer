import Foundation

/// Realistic sample content for the demo. Swap for Muse + SerpApi responses later.
enum Mock {
    static let me = Member(id: "devin", name: "Devin T", photo: "avatar-devin", isMe: true)
    static let sam = Member(id: "sam", name: "Sam Patel", photo: "avatar-sam")
    static let maya = Member(id: "maya", name: "Maya Chen", photo: "avatar-maya")
    static let jordan = Member(id: "jordan", name: "Jordan Lee", photo: "avatar-jordan")
    static let mom = Member(id: "mom", name: "Mom", photo: "avatar-mom")
    static let dad = Member(id: "dad", name: "Dad", photo: "avatar-dad")
    static let priya = Member(id: "priya", name: "Priya", photo: "avatar-priya")

    static let bea = Member(id: "bea", name: "Bea Santos")
    static let theo = Member(id: "theo", name: "Theo Park")
    static let ana = Member(id: "ana", name: "Ana Ruiz")
    static let kai = Member(id: "kai", name: "Kai Morgan")
    static let lu = Member(id: "lu", name: "Lu Chen")

    static let tripMembers = [me, sam, maya, jordan]
    static let roommates = [me, bea, theo, ana, kai, lu]

    // MARK: Dinner (a gathering: no flights, no stays, just where and who)

    static let dinnerDecisions: [Decision] = [
        Decision(title: "Day", symbol: "calendar", tint: .dates, state: .decided("Fri, 7:30 PM")),
        Decision(title: "Place", symbol: "fork.knife", tint: .stays, state: .voting("Olive & Ember leads")),
        Decision(title: "Who's in", symbol: "person.2", tint: .activities, state: .open("5 of 6 going")),
    ]

    static let dinnerMessages: [Message] = [
        Message(senderID: "theo", body: .text("ok bea's bday friday, where are we going"), time: "5:41 PM"),
        Message(senderID: "ana", body: .text("somewhere with real vegan stuff pls 🌱"), time: "5:42 PM"),
        Message(senderID: "kai", body: .text("not over like $40 i'm broke"), time: "5:42 PM"),
        Message(senderID: "devin", body: .text("@Muse where should we go for Bea's birthday dinner Friday? 6 of us, $40 each, one vegan, near Allston"), time: "5:44 PM"),
        Message(senderID: "planner", body: .planner(PlannerPost(
            text: "Three spots near Allston fit $40 each and have proper vegan mains. Olive & Ember takes groups of 6 at 7:30.",
            card: .init(title: "Dinner · Friday", rows: [
                .init(label: "Olive & Ember", detail: "Mediterranean · vegan menu · 0.4 mi", value: "$34"),
                .init(label: "Taqueria Luz", detail: "Mexican · vegan tacos · 0.6 mi", value: "$22"),
                .init(label: "Little Saigon Kitchen", detail: "Vietnamese · tofu pho · 0.3 mi", value: "$26"),
            ], action: "Vote in NxT")
        )), time: "5:44 PM"),
        Message(senderID: "lu", body: .text("olive & ember!! their mezze is so good"), time: "5:47 PM"),
    ]

    static let dinnerOptions: [BoardOption] = [
        BoardOption(category: .activities, title: "Olive & Ember", detail: "Mediterranean · 0.4 mi · takes 6 at 7:30", price: "$34", unit: "per person", tradeoff: "Full vegan menu and a quiet back room. Books up by Thursday.", source: "Google Maps", fetched: "just now", upVotes: 3, downVotes: 0, isTopPick: true),
        BoardOption(category: .activities, title: "Taqueria Luz", detail: "Mexican · 0.6 mi · walk-in", price: "$22", unit: "per person", tradeoff: "Cheapest and loud in a fun way. No reservations.", source: "Google Maps", fetched: "just now", upVotes: 1, downVotes: 0),
        BoardOption(category: .activities, title: "Little Saigon Kitchen", detail: "Vietnamese · 0.3 mi · step-free entrance", price: "$26", unit: "per person", tradeoff: "Closest, tofu pho is great. Small tables, might split us up.", source: "Google Maps", fetched: "just now", upVotes: 0, downVotes: 0),
    ]

    static let dinnerSteps: [AgentStep] = [
        AgentStep(tool: "Read the chat", detail: "Friday, 6 people, $40 each, one vegan", engine: "Muse Spark", duration: 0.4, credits: 1),
        AgentStep(tool: "Find restaurants", detail: "Near Allston · vegan options · groups of 6", engine: "SerpApi · google_maps", duration: 1.3, credits: 1),
    ]
    static let familyMembers = [me, mom, dad, priya]

    // MARK: Trip

    static let tripDecisions: [Decision] = [
        Decision(title: "Dates", symbol: "calendar", tint: .dates, state: .decided("Mar 26 – Apr 4")),
        Decision(title: "Budget", symbol: "dollarsign", tint: .money, state: .decided("$2,500 each")),
        Decision(title: "Flights", symbol: "airplane", tint: .flights, state: .voting("ANA leads, 3 of 4 voted")),
        Decision(title: "Stays", symbol: "bed.double", tint: .stays, state: .decided("Shinjuku + Kyoto")),
        Decision(title: "Things to do", symbol: "ticket", tint: .activities, state: .open("2 ideas, no votes yet")),
    ]

    static let tripMessages: [Message] = [
        Message(senderID: "planner", body: .event("Muse added to Japan crew · replies only when @mentioned"), time: "6:58 PM"),
        Message(senderID: "maya", body: .text("Okay Japan is actually happening??"), time: "7:02 PM"),
        Message(senderID: "sam", body: .text("I can only do late March. Mar 20–24 I'm stuck at a conference"), time: "7:03 PM"),
        Message(senderID: "jordan", body: .text("Budget is like $2,500 each?"), time: "7:04 PM"),
        Message(senderID: "maya", body: .text("Same, and I want at least 2 nights in Kyoto"), time: "7:05 PM"),
        Message(senderID: "devin", body: .text("@Muse can you find flights from Austin?"), time: "7:06 PM"),
        Message(senderID: "planner", body: .planner(PlannerPost(
            text: "Three round trips fit everyone's dates and the $2,500 budget. I skipped Mar 20–24 for Sam.",
            card: .init(title: "Flights · Austin → Tokyo", rows: [
                .init(label: "ANA via LAX", detail: "1 stop · 17h 40m", value: "$1,148"),
                .init(label: "JAL via DFW", detail: "1 stop · 16h 05m", value: "$1,312"),
                .init(label: "United via SFO", detail: "1 stop · leaves Mar 27", value: "$1,089"),
            ], action: "Vote in NxT"),
            trace: ["Read 5 messages", "Google Flights · 2.1s", "Checked calendars"]
        )), time: "7:06 PM"),
        Message(senderID: "sam", body: .text("ANA one looks good, voted"), time: "7:08 PM"),
    ]

    static let tripOptions: [BoardOption] = [
        BoardOption(category: .flights, title: "ANA", detail: "AUS → HND · via LAX · 17h 40m", price: "$1,148", unit: "per person", tradeoff: "Cheapest with a sane layover. Lands at Haneda, 30 min to Shinjuku.", source: "Google Flights", fetched: "2 min ago", upVotes: 3, downVotes: 0, myVote: .up, isTopPick: true, watchID: "demo-ana"),
        BoardOption(category: .flights, title: "JAL", detail: "AUS → NRT · via DFW · 16h 05m", price: "$1,312", unit: "per person", tradeoff: "Fastest, but Narita is 70 min from the city.", source: "Google Flights", fetched: "2 min ago", upVotes: 1, downVotes: 1, watchID: "demo-jal"),
        BoardOption(category: .flights, title: "United", detail: "AUS → HND · via SFO · 18h 10m", price: "$1,089", unit: "per person", tradeoff: "Lowest fare, but leaves a day later.", source: "Google Flights", fetched: "3 min ago", upVotes: 0, downVotes: 2),
        BoardOption(category: .stays, title: "Hotel Gracery Shinjuku", detail: "4.4 rating · 2 twin rooms · 5 nights", price: "$168", unit: "per room, night", tradeoff: "Central and walkable. Rooms are small.", source: "Google Hotels", fetched: "4 min ago", upVotes: 4, downVotes: 0, isTopPick: true, watchID: "demo-gracery"),
        BoardOption(category: .stays, title: "Kyoto Machiya House", detail: "4.8 rating · whole house · 3 nights", price: "$214", unit: "per night", tradeoff: "Traditional and roomy. 15 min walk to the station.", source: "Google Hotels", fetched: "4 min ago", upVotes: 4, downVotes: 0, isTopPick: true, watchID: "demo-machiya"),
        BoardOption(category: .activities, title: "teamLab Planets", detail: "Toyosu · 2 hours", price: "$28", unit: "per person", tradeoff: "Timed entry. Book two weeks ahead.", source: "Google Search", fetched: "6 min ago", upVotes: 0, downVotes: 0),
        BoardOption(category: .activities, title: "Fushimi Inari at sunrise", detail: "Kyoto · 3 hour hike", price: "Free", unit: "", tradeoff: "No crowds, but a 6 AM start.", source: "Google Maps", fetched: "6 min ago", upVotes: 0, downVotes: 0),
    ]

    /// What the backend searches for the Japan trip (backend/huddle/board.py).
    static let japanQuery = TripQuery(
        travelers: 4, budgetPerPerson: 2500,
        flights: [.init(from: "AUS", to: "HND", depart: "2027-03-26", return: "2027-04-04")],
        stays: [.init(area: "Shinjuku", checkIn: "2027-03-26", checkOut: "2027-03-30", rooms: 2),
                .init(area: "Kyoto Higashiyama", checkIn: "2027-03-30", checkOut: "2027-04-02", rooms: 1)],
        activities: ["top things to do, Tokyo", "top things to do, Kyoto"]
    )

    /// The car plan watches used RAV4 listings against the buyout price.
    static let carWatch = WatchRequest(
        category: "car", label: "Used RAV4 XLE near Austin", engine: "google_shopping",
        params: ["q": "2023 Toyota RAV4 XLE, ~37k mi, Austin"],
        detail: "2023 · about 37k miles · cheapest listing", unit: "per car"
    )

    static let itinerary: [ItineraryDay] = [
        ItineraryDay(day: 1, date: "Thu, Mar 26", city: "Tokyo", slots: [
            .init(time: "3:40 PM", title: "Land at Haneda", detail: "ANA NH 107 · Terminal 3"),
            .init(time: "5:30 PM", title: "Check in", detail: "Hotel Gracery Shinjuku"),
            .init(time: "8:00 PM", title: "Dinner at Omoide Yokocho", detail: "Yakitori alley · about $25 each"),
        ]),
        ItineraryDay(day: 2, date: "Fri, Mar 27", city: "Tokyo", slots: [
            .init(time: "10:00 AM", title: "teamLab Planets", detail: "If the group votes yes"),
            .init(time: "2:00 PM", title: "Tsukiji Outer Market", detail: "Lunch and wander"),
            .init(time: "6:30 PM", title: "Shibuya Sky at sunset", detail: "$18 each"),
        ]),
        ItineraryDay(day: 5, date: "Mon, Mar 30", city: "Kyoto", slots: [
            .init(time: "9:00 AM", title: "Shinkansen to Kyoto", detail: "Nozomi · 2h 15m"),
            .init(time: "1:00 PM", title: "Check in", detail: "Kyoto Machiya House"),
        ]),
    ]

    static let tripSteps: [AgentStep] = [
        AgentStep(tool: "Read the thread", detail: "Dates, budget, and who can't go when", engine: "Muse Spark", duration: 0.4, credits: 1),
        AgentStep(tool: "Search flights", detail: "AUS → HND / NRT · Mar 26 – Apr 4 · 4 adults", engine: "SerpApi · google_flights", duration: 2.1, credits: 1),
        AgentStep(tool: "Search stays", detail: "Shinjuku · 2 rooms · under $200 a night", engine: "SerpApi · google_hotels", duration: 1.8, credits: 1),
        AgentStep(tool: "Find things to do", detail: "Top rated in Tokyo and Kyoto", engine: "SerpApi · google_maps", duration: 1.2, credits: 1),
        AgentStep(tool: "Check calendars", detail: "Sam is away Mar 20–24", engine: "Calendar", duration: 0.3, credits: 0),
        AgentStep(tool: "Rank and summarize", detail: "Budget fit, travel time, votes", engine: "Muse Spark", duration: 1.6, credits: 2),
    ]

    static let tripSources: [SourceRef] = [
        .init(name: "Google Flights", detail: "3 itineraries"),
        .init(name: "Google Hotels", detail: "2 properties"),
        .init(name: "Google Maps", detail: "2 places"),
        .init(name: "Japan crew thread", detail: "12 messages"),
    ]

    // MARK: Car

    static let carDecisions: [Decision] = [
        Decision(title: "Keep a Toyota", symbol: "car", tint: .car, state: .decided("Everyone agrees")),
        Decision(title: "Buy out or return", symbol: "arrow.left.arrow.right", tint: .money, state: .voting("Buy out leads, 3 of 4")),
        Decision(title: "Dealer visit", symbol: "calendar", tint: .dates, state: .open("Not booked yet")),
    ]

    static let carMessages: [Message] = [
        Message(senderID: "dad", body: .text("Lease is up in 4 months. Do we just buy the RAV4 out?"), time: "8:12 PM"),
        Message(senderID: "mom", body: .text("We're already over on miles though"), time: "8:13 PM"),
        Message(senderID: "priya", body: .text("I'm driving to college next fall, I need something reliable"), time: "8:14 PM"),
        Message(senderID: "devin", body: .text("@Muse compare our options?"), time: "8:15 PM"),
        Message(senderID: "planner", body: .planner(PlannerPost(
            text: "Buying out looks best. Your buyout price is about $3,900 under what similar RAV4s sell for, and it skips roughly $1,140 in mileage fees.",
            card: .init(title: "RAV4 lease · 4 options", rows: [
                .init(label: "Buy out", detail: "60-month loan", value: "$478/mo"),
                .init(label: "Return & lease new", detail: "plus ~$1,140 fees", value: "$429/mo"),
            ], action: "Compare in NxT"),
            trace: ["Lease account (simulated)", "Google Shopping · 2.4s", "Cost model · 4 scenarios"]
        )), time: "8:15 PM"),
        Message(senderID: "mom", body: .text("Okay that's convincing. Can we talk to someone first?"), time: "8:17 PM"),
    ]

    static let lease = LeaseSnapshot(
        vehicle: "2023 RAV4 XLE", monthsRemaining: 4, monthlyPayment: 389,
        milesUsed: 37_600, milesAllowed: 36_000, residualValue: 24_180, marketValue: 28_050
    )

    static let leaseOptions: [LeaseOption] = [
        LeaseOption(title: "Buy out", monthly: "$478", total: "$28,680", totalLabel: "over 60 months", tradeoff: "You'd own a car worth about $3,900 more than you pay. No mileage fees.", votes: ["devin", "mom", "priya"], isRecommended: true),
        LeaseOption(title: "Return and lease new", monthly: "$429", total: "$16,584", totalLabel: "over 36 months, with fees", tradeoff: "Newest model and lowest commitment, but about $1,140 in mileage fees.", votes: ["dad"]),
        LeaseOption(title: "Trade in", monthly: "$512", total: "+$3,870", totalLabel: "equity toward the next car", tradeoff: "Uses your equity as a down payment. Best if you want something bigger.", votes: []),
        LeaseOption(title: "Extend 6 months", monthly: "$389", total: "$2,334", totalLabel: "over 6 months", tradeoff: "Buys time to decide while the miles keep adding up.", votes: []),
    ]

    static let assumptions: [Assumption] = [
        .init(label: "Buyout loan", value: "5.9% APR · 60 mo", source: "Simulated offer"),
        .init(label: "Market value", value: "$28,050", source: "Google Shopping · 14 listings"),
        .init(label: "Mileage fee", value: "$0.25 × 4,560 mi", source: "Lease terms (simulated)"),
        .init(label: "New RAV4 lease", value: "$429/mo · $2,999 down", source: "Google Search"),
        .init(label: "Miles per year", value: "About 15,000", source: "Your last 32 months"),
    ]

    static let carSteps: [AgentStep] = [
        AgentStep(tool: "Read the thread", detail: "Lease ends in 4 months, over on miles", engine: "Muse Spark", duration: 0.4, credits: 1),
        AgentStep(tool: "Load lease", detail: "Buyout price, payment, mileage", engine: "Simulated account", duration: 0.2, credits: 0),
        AgentStep(tool: "Price check", detail: "Used 2023 RAV4 XLE near Austin", engine: "SerpApi · google_shopping", duration: 2.4, credits: 1),
        AgentStep(tool: "Current offers", detail: "2026 RAV4 lease deals in Texas", engine: "SerpApi · google", duration: 1.5, credits: 1),
        AgentStep(tool: "Cost model", detail: "4 scenarios over 36 months", engine: "Calculator", duration: 0.6, credits: 0),
        AgentStep(tool: "Recommend", detail: "Plain-language summary", engine: "Muse Spark", duration: 1.3, credits: 2),
    ]

    static let carSources: [SourceRef] = [
        .init(name: "Google Shopping", detail: "14 listings"),
        .init(name: "Google Search", detail: "Toyota offers"),
        .init(name: "Lease account", detail: "Simulated"),
        .init(name: "Family thread", detail: "6 messages"),
    ]

    // MARK: Shared in from other apps

    static let sharedItems: [SharedItem] = [
        SharedItem(id: UUID(uuidString: "11111111-0000-0000-0000-000000000001")!, title: "Ichiran Ramen, Shinjuku", url: "https://www.instagram.com/reel/ichiran-shinjuku",
                   source: "Instagram", sharedBy: "Maya", planID: "japan", category: "Things to do",
                   note: "Open 24 hours. Solo booths, the line moves fast.", date: .now.addingTimeInterval(-60 * 14)),
        SharedItem(id: UUID(uuidString: "11111111-0000-0000-0000-000000000002")!, title: "Nara deer park day trip", url: "https://www.instagram.com/reel/nara-deer",
                   source: "Instagram", sharedBy: "Jordan", planID: "japan", category: "Things to do",
                   note: "45 min from Kyoto by train.", date: .now.addingTimeInterval(-60 * 60 * 2)),
        SharedItem(id: UUID(uuidString: "11111111-0000-0000-0000-000000000003")!, title: "Hakone onsen night", text: "what about one night at an onsen in Hakone??",
                   source: "WhatsApp", sharedBy: "Sam", planID: "japan", category: "Stays",
                   note: "Sam suggested this in Japan crew.", date: .now.addingTimeInterval(-60 * 60 * 5)),
        SharedItem(id: UUID(uuidString: "11111111-0000-0000-0000-000000000004")!, title: "2026 RAV4 Hybrid lease offer", url: "https://www.toyota.com/rav4/offers",
                   source: "Safari", sharedBy: "Dad", planID: "car", category: "Options",
                   note: "$399/mo, $2,999 down.", date: .now.addingTimeInterval(-60 * 60 * 26)),
    ]
}
