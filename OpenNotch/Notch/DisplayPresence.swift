import Combine

/// One display's share of the notch, with "Every display" on.
///
/// Every panel draws from the same `NotchViewModel`: one set of media,
/// calendar and activity sources however many screens there are. What each
/// panel owns is its geometry and whether it's the active one, the one the
/// pointer last reached. Only the active panel follows hover and opens; the
/// rest show the model's resting state, so a live activity peeks on every
/// screen while the open panel stays on one.
final class DisplayPresence: ObservableObject {
    @Published var metrics: NotchMetrics
    @Published var isActive: Bool
    /// Asks the window controller to make this the active panel.
    var claim: () -> Void = {}

    init(metrics: NotchMetrics, isActive: Bool) {
        self.metrics = metrics
        self.isActive = isActive
    }
}
