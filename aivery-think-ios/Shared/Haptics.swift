import UIKit

/// Centralized, pre-warmed haptics. Reusing prepared generators fires the tap with
/// minimal latency versus allocating a fresh generator on every call. The project
/// defaults to MainActor isolation, so these statics are main-actor safe.
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Warm up the Taptic Engine so the next tap is instant. Call when input gains focus.
    static func prepare() {
        light.prepare(); medium.prepare(); rigid.prepare(); soft.prepare()
        notify.prepare(); selection.prepare()
    }

    static func tapLight()  { light.impactOccurred();  light.prepare() }   // retry / minor
    static func tapMedium() { medium.impactOccurred(); medium.prepare() }  // send / delete
    static func tapRigid()  { rigid.impactOccurred() }                     // new chat (crisp)
    static func tapSoft()   { soft.impactOccurred();   soft.prepare() }    // picker chips
    static func success()   { notify.notificationOccurred(.success); notify.prepare() }
    static func warning()   { notify.notificationOccurred(.warning) }
    static func error()     { notify.notificationOccurred(.error) }
    static func select()    { selection.selectionChanged(); selection.prepare() }
}
