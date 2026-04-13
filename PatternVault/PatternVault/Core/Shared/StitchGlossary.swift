//
//  StitchGlossary.swift
//  PatternVault
//
//  Comprehensive glossary of knitting and crochet abbreviations.
//  107 entries covering standard stitches, increases, decreases, cables,
//  lace, colorwork, post stitches, amigurumi, construction terms,
//  Tunisian crochet, and UK/US terminology.
//
//  Sources: Craft Yarn Council, Tin Can Knits, Shelley Husband UK/US chart.
//

import Foundation

enum StitchGlossary {
    struct Entry: Identifiable {
        let id: String
        let abbreviation: String
        let fullName: String
        let description: String
        let craft: StitchCraftKind
        let category: Category

        enum Category: String, CaseIterable {
            case basicKnit = "Basic Knitting"
            case basicCrochet = "Basic Crochet"
            case increase = "Increases"
            case decrease = "Decreases"
            case cable = "Cables"
            case lace = "Lace"
            case colorwork = "Colorwork"
            case postStitch = "Post Stitches"
            case crochetSpecialty = "Crochet Specialty"
            case construction = "Construction"
            case tunisian = "Tunisian Crochet"
        }

        init(_ abbreviation: String, _ fullName: String, _ description: String, _ craft: StitchCraftKind, _ category: Category) {
            self.id = abbreviation.lowercased()
            self.abbreviation = abbreviation
            self.fullName = fullName
            self.description = description
            self.craft = craft
            self.category = category
        }
    }

    // swiftlint:disable function_body_length
    static let entries: [String: Entry] = {
        let list: [Entry] = [
            // MARK: - Basic Knitting
            Entry("k", "Knit", "Insert needle from left to right, wrap yarn, pull through. The most fundamental knitting stitch.", .knitting, .basicKnit),
            Entry("p", "Purl", "Insert needle from right to left, wrap yarn, pull through. The reverse of a knit stitch.", .knitting, .basicKnit),
            Entry("St st", "Stockinette Stitch", "Alternate knit rows and purl rows. Creates smooth V-shapes on the front, bumps on the back.", .knitting, .basicKnit),
            Entry("rev St st", "Reverse Stockinette", "Stockinette with the purl (bumpy) side as the right side.", .knitting, .basicKnit),
            Entry("garter st", "Garter Stitch", "Knit every stitch on every row. Creates a stretchy, ridged fabric that looks the same on both sides.", .knitting, .basicKnit),
            Entry("tbl", "Through Back Loop", "Work the stitch through the back leg instead of the front. Twists the stitch, tightening it.", .knitting, .basicKnit),
            Entry("sl", "Slip", "Move a stitch from left to right needle without working it. Default is purlwise unless stated otherwise.", .knitting, .basicKnit),
            Entry("sl1k", "Slip 1 Knitwise", "Slip one stitch by inserting needle as if to knit. Twists the stitch; used in decreases.", .knitting, .basicKnit),
            Entry("sl1p", "Slip 1 Purlwise", "Slip one stitch by inserting needle as if to purl. Keeps the stitch untwisted.", .knitting, .basicKnit),

            // MARK: - Basic Crochet (US terms)
            Entry("ch", "Chain", "Yarn over and pull through the loop on your hook. Forms the foundation of most crochet projects.", .crochet, .basicCrochet),
            Entry("slst", "Slip Stitch", "Insert hook, yarn over, pull through both the stitch and the loop on hook. Used for joining rounds.", .crochet, .basicCrochet),
            Entry("sc", "Single Crochet", "Insert hook, pull up a loop (2 loops on hook), yarn over, pull through both. The shortest crochet stitch. UK: dc.", .crochet, .basicCrochet),
            Entry("hdc", "Half Double Crochet", "Yarn over, insert hook, pull up a loop (3 loops), yarn over, pull through all 3. UK: htr.", .crochet, .basicCrochet),
            Entry("dc", "Double Crochet", "Yarn over, insert hook, pull up a loop, [yarn over, pull through 2] twice. A tall, versatile stitch. UK: tr.", .crochet, .basicCrochet),
            Entry("tr", "Treble Crochet", "Yarn over twice, insert hook, pull up a loop, [yarn over, pull through 2] three times. Very tall. UK: dtr.", .crochet, .basicCrochet),
            Entry("dtr", "Double Treble Crochet", "Yarn over three times, insert hook, [yarn over, pull through 2] four times. Extra-tall stitch. UK: trtr.", .crochet, .basicCrochet),
            Entry("BLO", "Back Loop Only", "Insert hook under only the back loop. Creates a ridged texture. Very common in amigurumi.", .crochet, .basicCrochet),
            Entry("FLO", "Front Loop Only", "Insert hook under only the front loop. Creates a ridged texture on the opposite side from BLO.", .crochet, .basicCrochet),

            // MARK: - Increases
            Entry("inc", "Increase", "Work two stitches into the same stitch to add one to your count.", .knitting, .increase),
            Entry("kfb", "Knit Front and Back", "Knit the front of a stitch, then knit the back of the same stitch. A simple increase with a small bar.", .knitting, .increase),
            Entry("pfb", "Purl Front and Back", "Purl the front, then purl the back of the same stitch. Purl-side version of kfb.", .knitting, .increase),
            Entry("M1", "Make One", "Lift the bar between stitches onto the left needle and knit through the back. Nearly invisible increase.", .knitting, .increase),
            Entry("m1l", "Make One Left", "Lift bar from front to back, knit through back loop. Left-leaning increase.", .knitting, .increase),
            Entry("m1r", "Make One Right", "Lift bar from back to front, knit through front loop. Right-leaning increase.", .knitting, .increase),
            Entry("M1P", "Make One Purlwise", "Lift the bar between stitches and purl into it twisted. Purl-side make-one increase.", .knitting, .increase),
            Entry("yo", "Yarn Over", "Wrap yarn over the needle to create a new stitch and a decorative eyelet hole. Essential for lace.", .knitting, .increase),

            // MARK: - Decreases
            Entry("dec", "Decrease", "Work two or more stitches together to reduce the count.", .knitting, .decrease),
            Entry("k2tog", "Knit 2 Together", "Insert needle into 2 stitches at once and knit them as one. Right-leaning decrease.", .knitting, .decrease),
            Entry("p2tog", "Purl 2 Together", "Insert needle into 2 stitches purlwise and purl together. Purl-side decrease.", .knitting, .decrease),
            Entry("ssk", "Slip, Slip, Knit", "Slip 2 knitwise one at a time, insert left needle through fronts, knit together. Left-leaning decrease.", .knitting, .decrease),
            Entry("ssp", "Slip, Slip, Purl", "Slip 2 knitwise one at a time, return to left needle, purl together through back loops. Left-leaning purl decrease.", .knitting, .decrease),
            Entry("sssk", "Slip, Slip, Slip, Knit", "Slip 3 knitwise one at a time, knit together through back loops. Double left-leaning decrease.", .knitting, .decrease),
            Entry("SKP", "Slip, Knit, Pass Over", "Slip 1, knit 1, pass slipped stitch over. Alternative left-leaning decrease.", .knitting, .decrease),
            Entry("SK2P", "Slip 1, K2tog, Pass Over", "Centered double decrease: slip 1, k2tog, pass slipped stitch over. Center stitch sits on top.", .knitting, .decrease),
            Entry("s2kp2", "Slip 2, Knit 1, Pass 2 Over", "Slip 2 together knitwise, knit 1, pass both over. Centered double decrease for lace.", .knitting, .decrease),
            Entry("cdd", "Central Double Decrease", "Slip 2 together knitwise, knit 1, pass slipped stitches over. Same as S2KP2.", .knitting, .decrease),
            Entry("psso", "Pass Slipped Stitch Over", "Lift a previously slipped stitch over the working stitch and off the needle.", .knitting, .decrease),
            Entry("p2sso", "Pass 2 Slipped Stitches Over", "Pass two previously slipped stitches over the working stitch.", .knitting, .decrease),
            Entry("sl1", "Slip 1", "Pass one stitch from left needle to right needle without working it.", .knitting, .decrease),
            Entry("sc2tog", "Single Crochet 2 Together", "Pull up a loop in each of 2 stitches (3 loops on hook), yarn over, pull through all 3.", .crochet, .decrease),
            Entry("dc2tog", "Double Crochet 2 Together", "Work a dc in each of 2 stitches stopping before final pull-through, then pull through all loops.", .crochet, .decrease),
            Entry("hdc2tog", "Half Double Crochet 2 Together", "Begin hdc in each of 2 stitches, yarn over, pull through all loops at once.", .crochet, .decrease),
            Entry("invdec", "Invisible Decrease", "Hook through front loops only of 2 stitches, yarn over, pull through both, yarn over, pull through remaining. Neater than sc2tog; essential for amigurumi.", .crochet, .decrease),

            // MARK: - Cables
            Entry("cn", "Cable Needle", "A short needle used to hold stitches temporarily during cable crossings.", .knitting, .cable),
            Entry("C4F", "Cable 4 Front", "Slip 2 to cable needle, hold in front, knit 2, knit 2 from cable needle. Left-twisting 4-stitch cable.", .knitting, .cable),
            Entry("C4B", "Cable 4 Back", "Slip 2 to cable needle, hold in back, knit 2, knit 2 from cable needle. Right-twisting 4-stitch cable.", .knitting, .cable),
            Entry("C6F", "Cable 6 Front", "Slip 3 to cable needle, hold in front, knit 3, knit 3 from cable needle. Left-twisting 6-stitch cable.", .knitting, .cable),
            Entry("C6B", "Cable 6 Back", "Slip 3 to cable needle, hold in back, knit 3, knit 3 from cable needle. Right-twisting 6-stitch cable.", .knitting, .cable),
            Entry("C8F", "Cable 8 Front", "Slip 4 to cable needle, hold in front, knit 4, knit 4 from cable needle. Wide left-twisting cable.", .knitting, .cable),
            Entry("C8B", "Cable 8 Back", "Slip 4 to cable needle, hold in back, knit 4, knit 4 from cable needle. Wide right-twisting cable.", .knitting, .cable),
            Entry("T3F", "Twist 3 Front", "Slip 2 to cn, hold front, purl 1, knit 2 from cn. Moves a knit column left on purl background.", .knitting, .cable),
            Entry("T3B", "Twist 3 Back", "Slip 1 to cn, hold back, knit 2, purl 1 from cn. Moves a knit column right on purl background.", .knitting, .cable),
            Entry("RT", "Right Twist", "2-stitch mini cable: skip first stitch, knit second, then knit first. No cable needle needed.", .knitting, .cable),
            Entry("LT", "Left Twist", "2-stitch mini cable: knit second stitch tbl, then knit first normally. No cable needle needed.", .knitting, .cable),

            // MARK: - Lace
            Entry("yfwd", "Yarn Forward", "Bring yarn to front between needles. UK term for yarn over between knit stitches.", .knitting, .lace),
            Entry("yon", "Yarn Over Needle", "Wrap yarn over needle. UK term for yarn over between a purl and a knit stitch.", .knitting, .lace),
            Entry("yrn", "Yarn Round Needle", "Wrap yarn completely around needle. UK term for yarn over between two purl stitches.", .knitting, .lace),
            Entry("nupps", "Nupps", "A bobble made by working multiple yarn overs into one stitch, then purling them together on the return row. Common in Estonian lace.", .knitting, .lace),

            // MARK: - Colorwork
            Entry("MC", "Main Color", "The primary or background color in a multi-color pattern.", .knitting, .colorwork),
            Entry("CC", "Contrasting Color", "The secondary color(s). Multiple contrast colors are labeled CC1, CC2, CC3.", .knitting, .colorwork),

            // MARK: - Crochet Post Stitches
            Entry("FPdc", "Front Post Double Crochet", "Yarn over, insert hook front-to-back-to-front around the post of the stitch below, complete a dc. Creates a raised stitch.", .crochet, .postStitch),
            Entry("BPdc", "Back Post Double Crochet", "Yarn over, insert hook back-to-front-to-back around the post below, complete a dc. Creates a raised stitch on back.", .crochet, .postStitch),
            Entry("FPtr", "Front Post Treble Crochet", "Work a treble crochet around the front post of the stitch below.", .crochet, .postStitch),
            Entry("BPtr", "Back Post Treble Crochet", "Work a treble crochet around the back post of the stitch below.", .crochet, .postStitch),
            Entry("FPhdc", "Front Post Half Double Crochet", "Work an hdc around the front post of the stitch below.", .crochet, .postStitch),
            Entry("BPhdc", "Back Post Half Double Crochet", "Work an hdc around the back post of the stitch below.", .crochet, .postStitch),

            // MARK: - Crochet Specialty
            Entry("bobble", "Bobble", "Work several dc into one stitch, leaving last loop of each on hook, yarn over, pull through all. Creates a raised bump.", .crochet, .crochetSpecialty),
            Entry("cl", "Cluster", "Like a bobble but stitches are worked into consecutive stitches and joined at the top.", .crochet, .crochetSpecialty),
            Entry("pc", "Popcorn Stitch", "Work several complete dc into one stitch, remove hook, insert into first dc, grab dropped loop, pull through. Pronounced rounded bump.", .crochet, .crochetSpecialty),
            Entry("sh", "Shell", "Work multiple stitches (often 5 dc) into the same stitch or space to create a fan shape.", .crochet, .crochetSpecialty),
            Entry("MR", "Magic Ring", "Create an adjustable loop to begin crocheting in the round. Pull tight to close the center hole. Essential for amigurumi.", .crochet, .crochetSpecialty),

            // MARK: - Construction & Technique
            Entry("CO", "Cast On", "Put initial stitches onto your needle to begin knitting. Methods include long-tail, cable, provisional.", .knitting, .construction),
            Entry("BO", "Bind Off", "Secure live stitches so they don't unravel. UK term: Cast Off.", .knitting, .construction),
            Entry("pm", "Place Marker", "Slide a stitch marker onto your needle to mark a position like the beginning of a round.", .knitting, .construction),
            Entry("sm", "Slip Marker", "Slide the marker from left needle to right as you reach it.", .knitting, .construction),
            Entry("RS", "Right Side", "The public-facing side of your work.", .knitting, .construction),
            Entry("WS", "Wrong Side", "The inside or back of your work.", .knitting, .construction),
            Entry("dpn", "Double-Pointed Needles", "4-5 short needles with points at both ends for knitting small tubes like socks and mittens.", .knitting, .construction),
            Entry("rnd", "Round", "One complete circuit when working in the round (vs. a row which is worked flat).", .knitting, .construction),
            Entry("rep", "Repeat", "Work the indicated section again as many times as specified.", .knitting, .construction),
            Entry("rem", "Remaining", "Stitches still on your needle or hook.", .knitting, .construction),
            Entry("alt", "Alternate", "Work the instruction on every other row or round.", .knitting, .construction),
            Entry("beg", "Beginning", "The start of a row, round, or section.", .knitting, .construction),
            Entry("cont", "Continue", "Keep working in the established pattern.", .knitting, .construction),
            Entry("foll", "Following", "The next row, round, or instruction.", .knitting, .construction),
            Entry("tog", "Together", "Work the specified stitches as one (e.g., k2tog).", .knitting, .construction),
            Entry("st", "Stitch", "An individual loop on your needle or hook.", .knitting, .construction),
            Entry("sp", "Space", "A gap in the fabric, usually from a chain or yarn over. Commonly ch-sp in crochet.", .crochet, .construction),
            Entry("w&t", "Wrap and Turn", "Wrap yarn around next stitch, turn work. Used in short rows to prevent holes.", .knitting, .construction),
            Entry("DS", "Double Stitch", "German short rows: pull yarn over needle so previous stitch forms two legs. Cleaner than wrap and turn.", .knitting, .construction),
            Entry("wyif", "With Yarn in Front", "Hold working yarn on the side facing you while working the next instruction.", .knitting, .construction),
            Entry("wyib", "With Yarn in Back", "Hold working yarn on the side away from you.", .knitting, .construction),
            Entry("kwise", "Knitwise", "Insert needle as if to knit (left to right through the front).", .knitting, .construction),
            Entry("pwise", "Purlwise", "Insert needle as if to purl (right to left through the front).", .knitting, .construction),
            Entry("k1B", "Knit 1 Below", "Knit into the stitch one row below. Creates textured fabric; used in brioche.", .knitting, .construction),
            Entry("pat", "Pattern", "The stitch pattern or instructions being followed.", .knitting, .construction),

            // MARK: - Tunisian Crochet
            Entry("Tss", "Tunisian Simple Stitch", "Insert hook under front vertical bar, pull up a loop (forward pass), work off in pairs (return pass).", .crochet, .tunisian),
            Entry("Tks", "Tunisian Knit Stitch", "Insert hook between front and back bars (through the stitch center), pull up a loop. Resembles stockinette.", .crochet, .tunisian),
            Entry("Tps", "Tunisian Purl Stitch", "Yarn to front, insert hook under front bar, yarn over from back, pull through. Bumpy texture like purl.", .crochet, .tunisian),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()
    // swiftlint:enable function_body_length

    static func lookup(_ abbreviation: String) -> Entry? {
        let key = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let entry = entries[key] { return entry }
        // Handle numbered variants (k5 → k, p3 → p, c4f → c4f)
        let base = key.replacingOccurrences(of: "\\d+$", with: "", options: .regularExpression)
        return entries[base]
    }

    static var allEntries: [Entry] {
        entries.values.sorted { $0.abbreviation.lowercased() < $1.abbreviation.lowercased() }
    }

    static func entriesForCraft(_ craft: StitchCraftKind) -> [Entry] {
        allEntries.filter { $0.craft == craft }
    }

    static func entriesForCategory(_ category: Entry.Category) -> [Entry] {
        allEntries.filter { $0.category == category }
    }
}
