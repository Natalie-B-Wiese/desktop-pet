import Foundation

/// A unit the converter knows, defined by how to get to and from its category's base unit.
struct ConvertUnit: Identifiable, Hashable {
    let symbol: String
    let name: String
    /// Converts a value in this unit to the base unit.
    let toBase: (Double) -> Double
    /// Converts a value in the base unit to this unit.
    let fromBase: (Double) -> Double
    /// Reads a typed amount in this unit. Most units take math like "5+2".
    var read: (String) -> Result<Double, Failure> = { text in
        MathEvaluator.evaluate(text).mapError { Failure(message: $0.message) }
    }
    /// Shows an amount in this unit. Most units show a number rounded to 6 decimal places.
    var show: (Double) -> String = { MathEvaluator.format($0, maxFractionDigits: 6) }

    struct Failure: Error { var message: String }

    var id: String { symbol }

    /// A unit that's a plain multiple of the base unit.
    init(_ symbol: String, _ name: String, factor: Double) {
        self.init(symbol, name, toBase: { $0 * factor }, fromBase: { $0 / factor })
    }

    init(_ symbol: String, _ name: String, toBase: @escaping (Double) -> Double, fromBase: @escaping (Double) -> Double) {
        self.symbol = symbol
        self.name = name
        self.toBase = toBase
        self.fromBase = fromBase
    }

    static func == (a: ConvertUnit, b: ConvertUnit) -> Bool { a.symbol == b.symbol }
    func hash(into hasher: inout Hasher) { hasher.combine(symbol) }
}

/// What the Convert tab shows for a typed amount.
struct Conversion {
    var answer: Result<String, ConvertUnit.Failure>
    /// Colors only: the color, for the swatch.
    var color: RGBColor?
    /// Colors only: how the amount was read, like "H 32° · S 100% · L 50%".
    var breakdown: String?
    /// Ranges only: a heads-up under the answer, like "Outside 0 – 1".
    var note: String?
}

/// A group of units that convert into each other, like lengths or colors.
struct ConvertCategory: Identifiable, Hashable {
    enum Kind {
        /// Units holding one number, which convert through a base unit.
        case numbers([ConvertUnit])
        /// Ways of writing a color, which convert through `RGBColor`.
        case colors([ColorUnit])
        /// Maps a number from one range onto another, with typed ranges instead of units. See `mapRange`.
        case range
    }

    let name: String
    let kind: Kind
    /// The units shown when the category is first picked.
    let defaultFrom: String
    let defaultTo: String

    var id: String { name }

    init(name: String, units: [ConvertUnit], defaultFrom: String, defaultTo: String) {
        self.init(name: name, kind: .numbers(units), defaultFrom: defaultFrom, defaultTo: defaultTo)
    }

    init(name: String, kind: Kind, defaultFrom: String, defaultTo: String) {
        self.name = name
        self.kind = kind
        self.defaultFrom = defaultFrom
        self.defaultTo = defaultTo
    }

    var isColor: Bool {
        if case .colors = kind { true } else { false }
    }

    var isRange: Bool {
        if case .range = kind { true } else { false }
    }

    /// The units in the pop-up menus.
    var menu: [(symbol: String, name: String)] {
        switch kind {
        case .numbers(let units): units.map { ($0.symbol, $0.name) }
        case .colors(let units): units.map { ($0.symbol, $0.name) }
        case .range: []
        }
    }

    func has(_ symbol: String) -> Bool {
        menu.contains { $0.symbol == symbol }
    }

    /// Converts typed text between two of this category's units, given by symbol.
    func convert(_ text: String, from: String, to: String) -> Conversion {
        switch kind {
        case .numbers(let units):
            let from = units.first { $0.symbol == from }!, to = units.first { $0.symbol == to }!
            return Conversion(answer: from.read(text).map { to.show(to.fromBase(from.toBase($0))) })
        case .colors(let units):
            let from = units.first { $0.symbol == from }!, to = units.first { $0.symbol == to }!
            switch from.read(text) {
            case .success(let numbers):
                let color = from.toRGB(numbers)
                return Conversion(answer: .success(to.show(to.fromRGB(color))), color: color, breakdown: from.breakdown(numbers))
            case .failure(let failure):
                return Conversion(answer: .failure(failure))
            }
        case .range:
            preconditionFailure("Ranges have no units; use mapRange")
        }
    }

    /// Maps an amount from one range onto another, like 0.5 in 0–1 → 50 in 0–100. Every box takes math.
    /// Backwards ranges work (0–100 → 100–0 flips a value). An amount outside the first range carries on
    /// past the ends of the second (1.5 → 150), with a note saying so.
    static func mapRange(_ text: String, from: (min: String, max: String), to: (min: String, max: String)) -> Conversion {
        let ends = [from.min, from.max, to.min, to.max].map { $0.trimmingCharacters(in: .whitespaces) }
        guard !ends.contains(where: \.isEmpty) else {
            return Conversion(answer: .failure(ConvertUnit.Failure(message: "Fill in both ends of each range")))
        }
        do {
            let value = try MathEvaluator.evaluate(text).get()
            let numbers = try ends.map { try MathEvaluator.evaluate($0).get() }
            let (fromMin, fromMax, toMin, toMax) = (numbers[0], numbers[1], numbers[2], numbers[3])
            guard fromMin != fromMax else {
                return Conversion(answer: .failure(ConvertUnit.Failure(message: "The range can't be zero")))
            }
            let fraction = (value - fromMin) / (fromMax - fromMin)
            let answer = toMin + fraction * (toMax - toMin)
            let note = (0...1).contains(fraction) ? nil : "Outside \(ends[0]) – \(ends[1])"
            return Conversion(answer: .success(MathEvaluator.format(answer, maxFractionDigits: 6)), note: note)
        } catch let failure as MathEvaluator.Failure {
            return Conversion(answer: .failure(ConvertUnit.Failure(message: failure.message)))
        } catch {
            return Conversion(answer: .failure(ConvertUnit.Failure(message: "\(error)")))
        }
    }

    static func == (a: ConvertCategory, b: ConvertCategory) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// Web pages' default font size, which 1 rem stands for.
    static let remPixels: Double = 16

    /// In menu order: the most used first, then Screen, then Range (which has no units).
    static let all: [ConvertCategory] = [
        // Base: seconds. "h:mm" reads and shows time like a clock, so 69 minutes is 1:09.
        ConvertCategory(name: "Time", units: [
            ConvertUnit("sec", "seconds", factor: 1),
            ConvertUnit("min", "minutes", factor: 60),
            ConvertUnit("hr", "hours", factor: 3600),
            ConvertUnit("day", "days", factor: 86400),
            hoursMinutes,
        ], defaultFrom: "min", defaultTo: "h:mm"),
        // Base: meters.
        ConvertCategory(name: "Length", units: [
            ConvertUnit("mm", "millimeters", factor: 0.001),
            ConvertUnit("cm", "centimeters", factor: 0.01),
            ConvertUnit("m", "meters", factor: 1),
            ConvertUnit("km", "kilometers", factor: 1000),
            ConvertUnit("in", "inches", factor: 0.0254),
            ConvertUnit("ft", "feet", factor: 0.3048),
            ConvertUnit("yd", "yards", factor: 0.9144),
            ConvertUnit("mi", "miles", factor: 1609.344),
        ], defaultFrom: "in", defaultTo: "cm"),
        // Base: grams.
        ConvertCategory(name: "Weight", units: [
            ConvertUnit("g", "grams", factor: 1),
            ConvertUnit("kg", "kilograms", factor: 1000),
            ConvertUnit("oz", "ounces", factor: 28.349523125),
            ConvertUnit("lb", "pounds", factor: 453.59237),
        ], defaultFrom: "lb", defaultTo: "kg"),
        // Base: degrees Celsius.
        ConvertCategory(name: "Temperature", units: [
            ConvertUnit("°C", "Celsius", factor: 1),
            ConvertUnit("°F", "Fahrenheit", toBase: { ($0 - 32) * 5 / 9 }, fromBase: { $0 * 9 / 5 + 32 }),
            ConvertUnit("K", "Kelvin", toBase: { $0 - 273.15 }, fromBase: { $0 + 273.15 }),
        ], defaultFrom: "°F", defaultTo: "°C"),
        // Base: milliliters. Cups, pints and so on are US measures.
        ConvertCategory(name: "Volume", units: [
            ConvertUnit("ml", "milliliters", factor: 1),
            ConvertUnit("L", "liters", factor: 1000),
            ConvertUnit("tsp", "teaspoons", factor: 4.92892159375),
            ConvertUnit("tbsp", "tablespoons", factor: 14.78676478125),
            ConvertUnit("fl oz", "fluid ounces", factor: 29.5735295625),
            ConvertUnit("cup", "cups", factor: 236.5882365),
            ConvertUnit("pt", "pints", factor: 473.176473),
            ConvertUnit("qt", "quarts", factor: 946.352946),
            ConvertUnit("gal", "gallons", factor: 3785.411784),
        ], defaultFrom: "cup", defaultTo: "ml"),
        // Through red, green and blue from 0 to 1. See ColorConverter.swift.
        ConvertCategory(name: "Color", kind: .colors(ColorUnit.all), defaultFrom: "hex", defaultTo: "rgb"),
        // Base: CSS pixels. 1pt is 4/3 px; 1rem is 16px.
        ConvertCategory(name: "Screen", units: [
            ConvertUnit("px", "pixels", factor: 1),
            ConvertUnit("pt", "points", factor: 4.0 / 3.0),
            ConvertUnit("rem", "rem (16px)", factor: remPixels),
        ], defaultFrom: "px", defaultTo: "rem"),
        // Two typed ranges instead of units. See `mapRange`.
        ConvertCategory(name: "Range", kind: .range, defaultFrom: "", defaultTo: ""),
    ]

    /// Hours and minutes, like "1:09" (or "1:09:30" with seconds). Typed in like the Math page's Time tab,
    /// so "1:09", "1h 9m" and "1:00 + 9" all work, and a plain number is minutes. Unlike the Time tab,
    /// minutes can go past 59 here: converting is a handy way to tidy "5:70" into 6:10.
    private static let hoursMinutes: ConvertUnit = {
        var unit = ConvertUnit("h:mm", "hours:minutes", factor: 1)
        unit.read = { text in
            TimeEvaluator.seconds(text, allowOverflow: true).map(Double.init).mapError { ConvertUnit.Failure(message: $0.message) }
        }
        unit.show = { TimeEvaluator.durationText(Int($0.rounded())) }
        return unit
    }()

    static func named(_ name: String?) -> ConvertCategory? {
        all.first { $0.name == name }
    }
}
