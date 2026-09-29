import Foundation

/// A pet's look: its pixel-art image and what its recolorable parts are called.
///
/// In the image, pure red, green and blue pixels are the three recolorable parts (slots 0, 1, 2);
/// every other color is fixed. A part the image doesn't use is simply hidden in Customize.
/// To add a character (say, a dog), add its PNG to Resources and an entry to `all`.
struct PetCharacter: Identifiable, Equatable {
    let id: String
    /// The PNG's name in the app bundle, without ".png".
    let imageName: String
    /// Names for the red, green and blue parts, in that order.
    let partNames: [String]

    static let cat = PetCharacter(id: "cat", imageName: "pet", partNames: ["Body", "Accents", "Eyes"])

    static let all = [cat]

    /// The character in use. (Only the cat for now.)
    static var current: PetCharacter { cat }
}
