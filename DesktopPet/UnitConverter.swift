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

/// A group of units that convert into each other, like lengths.
struct ConvertCategory: Identifiable, Hashable {
    let name: String
    let units: [ConvertUnit]
    /// The units shown when the category is first picked.
    let defaultFrom: String
    let defaultTo: String

    var id: String { name }

    func unit(_ symbol: String?) -> ConvertUnit? {
        units.first { $0.symbol == symbol }
    }

    func convert(_ value: Double, from: ConvertUnit, to: ConvertUnit) -> Double {
        to.fromBase(from.toBase(value))
    }

    static func == (a: ConvertCategory, b: ConvertCategory) -> Bool { a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// Web pages' default font size, which 1 rem stands for.
    static let remPixels: Double = 16

    static let all: [ConvertCategory] = [
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
        // Base: CSS pixels. 1pt is 4/3 px; 1rem is 16px.
        ConvertCategory(name: "Screen", units: [
            ConvertUnit("px", "pixels", factor: 1),
            ConvertUnit("pt", "points", factor: 4.0 / 3.0),
            ConvertUnit("rem", "rem (16px)", factor: remPixels),
        ], defaultFrom: "px", defaultTo: "rem"),
        // Base: seconds. "h:mm" reads and shows time like a clock, so 69 minutes is 1:09.
        ConvertCategory(name: "Time", units: [
            ConvertUnit("sec", "seconds", factor: 1),
            ConvertUnit("min", "minutes", factor: 60),
            ConvertUnit("hr", "hours", factor: 3600),
            ConvertUnit("day", "days", factor: 86400),
            hoursMinutes,
        ], defaultFrom: "min", defaultTo: "h:mm"),
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
