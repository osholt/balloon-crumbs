import CarPlay
import CoreLocation
import Flutter
import MapLibre
import MapKit
import UIKit

/// Keeps asynchronous CarPlay template completions tied to the connection that
/// created them. A phone-side ride start can publish a navigation snapshot while
/// the head unit is still installing its root template; applying template state
/// before that completion, or accepting a completion from a disconnected scene,
/// can make CarPlay raise an Objective-C exception instead of returning an error.
struct CarPlaySceneLifecycle {
  private(set) var generation = 0
  private(set) var rootReady = false

  mutating func beginConnection() -> Int {
    generation &+= 1
    rootReady = false
    return generation
  }

  mutating func completeRootPresentation(
    generation completedGeneration: Int,
    succeeded: Bool
  ) -> Bool {
    guard completedGeneration == generation, succeeded else { return false }
    rootReady = true
    return true
  }

  mutating func disconnect() {
    generation &+= 1
    rootReady = false
  }
}

/// Owns the navigation-app CarPlay scene. Navigation apps must use the
/// window-bearing delegate callback and place a `CPMapTemplate` at the root.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate,
  CPMapTemplateDelegate, CPSearchTemplateDelegate
{
  private var mapTemplate: CPMapTemplate?
  private var mapViewController: CarPlayNavigationViewController?
  private var statusTemplate: CPListTemplate?
  private var navigationSession: CPNavigationSession?
  private var activeRouteID: String?
  private var activeManeuverKey: String?
  private var activeManeuver: CPManeuver?
  private var rideStartPrompt: [String: Any]?
  private var isShowingPanningInterface = false
  private var rideMenuButton: CPBarButton?
  private var surfaceMode = "unavailable"
  private var canPlanRoute = false
  private var canFreeRoam = false
  private var mapOrientation = "directionUp"
  private var voiceMuted = true
  private var submittedSearchText = ""
  private weak var interfaceController: CPInterfaceController?
  private var sceneLifecycle = CarPlaySceneLifecycle()

  /// The request the presented alert is asking about, so the same question is
  /// not raised twice and a question that has gone away takes its alert with
  /// it.

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    let connectionGeneration = sceneLifecycle.beginConnection()
    let mapViewController = CarPlayNavigationViewController()
    let mapTemplate = CPMapTemplate()
    let statusTemplate = CarPlayStatusTemplate.makeTemplate()

    self.mapTemplate = mapTemplate
    self.mapViewController = mapViewController
    self.statusTemplate = statusTemplate
    self.interfaceController = interfaceController
    mapViewController.onReport = { [weak self] in
      self?.presentReportActions()
    }
    mapViewController.onEmergency = { [weak self] in
      self?.presentEmergencyConfirmation()
    }
    mapViewController.onLeave = { [weak self] in
      self?.presentLeaveConfirmation()
    }
    let rideMenuButton = statusButton(
      interfaceController: interfaceController,
      template: statusTemplate
    )
    self.rideMenuButton = rideMenuButton

    window.rootViewController = mapViewController
    mapTemplate.mapDelegate = self
    mapTemplate.automaticallyHidesNavigationBar = true
    mapTemplate.hidesButtonsWithNavigationBar = false
    mapTemplate.guidanceBackgroundColor = CarPlayPalette.primaryPanelFill
    mapTemplate.mapButtons = []
    // Phone landscape puts its compact ride menu at the leading edge. Keep the
    // same learned location in the car; CarPlay still owns the navigation bar
    // and lays its manoeuvre card below it.
    mapTemplate.leadingNavigationBarButtons = [rideMenuButton]
    // Apple's header explicitly says a failed presentation throws when no
    // completion is supplied. More importantly, a navigation session must not
    // start until this root has actually been accepted by the head unit. The
    // phone can publish Start ride while this asynchronous operation is in
    // flight, which is the field crash reported in #441.
    interfaceController.setRootTemplate(mapTemplate, animated: false) {
      [weak self, weak interfaceController] success, error in
      guard
        let self,
        let interfaceController,
        self.interfaceController === interfaceController
      else { return }
      let becameReady = self.sceneLifecycle.completeRootPresentation(
        generation: connectionGeneration,
        succeeded: success
      )
      guard becameReady else {
        if let error {
          NSLog("CarPlay root template was not presented: %@", error.localizedDescription)
        }
        return
      }
      (UIApplication.shared.delegate as? AppDelegate)?.carPlayDidConnect(self)
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    // A delayed disconnect from an earlier scene must not cancel the current
    // navigation session or clear its view hierarchy.
    guard self.interfaceController === interfaceController else { return }
    sceneLifecycle.disconnect()
    navigationSession?.cancelTrip()
    navigationSession = nil
    window.rootViewController = nil
    self.interfaceController = nil
    mapTemplate = nil
    mapViewController = nil
    statusTemplate = nil
    rideMenuButton = nil
    rideStartPrompt = nil
    surfaceMode = "unavailable"
    canPlanRoute = false
    canFreeRoam = false
    submittedSearchText = ""
    (UIApplication.shared.delegate as? AppDelegate)?.carPlayDidDisconnect(self)
  }

  func apply(snapshot: [String: Any]) {
    mapViewController?.apply(snapshot: snapshot)
    if let statusTemplate {
      CarPlayStatusTemplate.apply(snapshot: snapshot, to: statusTemplate)
    }
    // App-owned map/status views can accept data while the root is installing,
    // but CarPlay template and navigation APIs cannot. AppDelegate retains the
    // same snapshot and replays it after the root completion above.
    guard sceneLifecycle.rootReady else { return }
    updateSurfaceActions(snapshot)
    updateNavigationSession(snapshot: snapshot)
    updateRideStart(snapshot["rideStart"] as? [String: Any])
  }

  func apply(viewport: [String: Any]) {
    mapViewController?.apply(viewport: viewport)
  }

  func apply(mapStyle: [String: Any]) {
    mapViewController?.apply(mapStyle: mapStyle)
  }

  @available(iOS 17.4, *)
  func mapTemplateShouldProvideNavigationMetadata(_ mapTemplate: CPMapTemplate) -> Bool {
    true
  }

  func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {
    isShowingPanningInterface = true
    mapTemplate.leadingNavigationBarButtons = [
      CPBarButton(title: "Done") { _ in
        mapTemplate.dismissPanningInterface(animated: true)
      }
    ]
  }

  func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {
    isShowingPanningInterface = false
    updateLeadingNavigationButtons()
  }

  func mapTemplate(
    _ mapTemplate: CPMapTemplate,
    panWith direction: CPMapTemplate.PanDirection
  ) {
    mapViewController?.pan(direction: direction)
  }

  func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
    mapViewController?.beginPanGesture()
  }

  func mapTemplate(
    _ mapTemplate: CPMapTemplate,
    didUpdatePanGestureWithTranslation translation: CGPoint,
    velocity: CGPoint
  ) {
    mapViewController?.updatePanGesture(translation: translation)
  }

  func mapTemplate(
    _ mapTemplate: CPMapTemplate,
    didEndPanGestureWithVelocity velocity: CGPoint
  ) {
    mapViewController?.endPanGesture()
  }

  /// Keep the phone's turn/marker symbol visible beside the instruction. The
  /// default layout is allowed to discard it when the card gets tight, which
  /// made marker mode look like ordinary navigation on smaller head units.
  func mapTemplate(
    _ mapTemplate: CPMapTemplate,
    displayStyleFor maneuver: CPManeuver
  ) -> CPManeuverDisplayStyle {
    .leadingSymbol
  }

  private func updateNavigationSession(snapshot: [String: Any]) {
    guard sceneLifecycle.rootReady else { return }
    // A CPNavigationSession always owns Apple's trip-estimate panel. There is
    // no supported API to hide that panel while retaining the manoeuvre card,
    // so the active ride now uses the app-owned guidance view on the map
    // canvas. Cancel a session left by an earlier build/connection.
    navigationSession?.cancelTrip()
    navigationSession = nil
    activeRouteID = nil
    activeManeuverKey = nil
    activeManeuver = nil
    return

    // Retained temporarily below as reference for the dashboard projection;
    // no execution reaches this Apple-template path.
    let marker = snapshot["marker"] as? [String: Any]
    let guidanceTitle = nonEmptyString(marker?["title"])
      ?? nonEmptyString(snapshot["guidanceTitle"])
    let terminalGuidance = marker == nil
      && guidanceTitle?.lowercased().contains("no more turns") == true
    guard
      let guidanceTitle,
      !terminalGuidance,
      let mapTemplate,
      let routePoints = snapshot["routePoints"] as? [[String: Any]],
      let first = coordinate(from: routePoints.first),
      let last = coordinate(from: routePoints.last),
      routePoints.count >= 2
    else {
      navigationSession?.cancelTrip()
      navigationSession = nil
      activeRouteID = nil
      activeManeuverKey = nil
      activeManeuver = nil
      return
    }

    let routeName = nonEmptyString(snapshot["routeName"]) ?? "Current route"
    let routeID =
      nonEmptyString(snapshot["routeId"])
      ?? "\(routePoints.count):\(first.latitude),\(first.longitude):\(last.latitude),\(last.longitude)"
    if navigationSession == nil || routeID != activeRouteID {
      navigationSession?.cancelTrip()
      let origin = MKMapItem(placemark: MKPlacemark(coordinate: first))
      origin.name = "Recovery start"
      let destination = MKMapItem(placemark: MKPlacemark(coordinate: last))
      destination.name = routeName
      let choice = CPRouteChoice(
        summaryVariants: [routeName],
        additionalInformationVariants: ["Recovery road route"],
        selectionSummaryVariants: [routeName]
      )
      let trip = CPTrip(origin: origin, destination: destination, routeChoices: [choice])
      navigationSession = mapTemplate.startNavigationSession(for: trip)
      activeRouteID = routeID
      activeManeuverKey = nil
      activeManeuver = nil
    }

    guard let navigationSession else { return }
    let title = guidanceTitle

    let markerDetail = nonEmptyString(marker?["detail"])
    let roadName = markerDetail ?? nonEmptyString(snapshot["guidanceRoadName"])
    let isMarkerMode = marker != nil
    let distance = max(0, (snapshot["guidanceDistanceMeters"] as? NSNumber)?.doubleValue ?? 0)
    let markerStage = nonEmptyString(marker?["stage"])
    // The key deliberately excludes the distance (#443).
    //
    // It used to include `displayTitle`, which carries the formatted distance —
    // so every position fix produced a new key, a new CPManeuver, and CarPlay
    // animated the card again. The rider saw the banner wiping constantly rather
    // than on each new direction.
    //
    // The distance now travels as a travel estimate instead, which is the API
    // CarPlay expects to change continuously, and is also what the instrument
    // cluster reads — it showed "— km" because nothing ever set it (#447).
    let maneuverKey = "\(isMarkerMode)|\(markerStage ?? "")|\(title)|\(roadName ?? "")"
    let maneuver: CPManeuver
    if activeManeuverKey == maneuverKey, let existing = activeManeuver {
      maneuver = existing
    } else {
      maneuver = CPManeuver()
      // The instruction alone. The distance used to be prefixed here, which
      // was fine only because the manoeuvre was rebuilt on every fix — now that
      // it is built once, a baked-in distance would freeze at its first value.
      // CarPlay renders the distance from the travel estimate below.
      maneuver.instructionVariants = [title]
      let symbol = isMarkerMode
        ? markerSymbol(for: markerStage)
        : maneuverSymbol(for: title)
      maneuver.symbolImage = symbol
      maneuver.dashboardSymbolImage = symbol
      maneuver.cardBackgroundColor = CarPlayPalette.primaryPanelFill
      if #available(iOS 17.4, *) {
        maneuver.maneuverType = isMarkerMode ? .noTurn : maneuverType(for: title)
        maneuver.roadFollowingManeuverVariants = roadName.map { [$0] }
        navigationSession.add([maneuver])
      }
      navigationSession.upcomingManeuvers = [maneuver]
      activeManeuverKey = maneuverKey
      activeManeuver = maneuver
    }
    // Every update, not only a new manoeuvre: this is the number the card and the
    // instrument cluster count down, and it is in the rider's own units so the
    // car agrees with the phone (#447).
    if distance > 0, !isMarkerMode {
      let usesMiles = (snapshot["distanceUnit"] as? String) == "miles"
      let remaining = usesMiles
        ? Measurement(value: distance / 1_609.344, unit: UnitLength.miles)
        : Measurement(value: distance, unit: UnitLength.meters)
      // `updateEstimates(_:for:)`, not `updateTravelEstimates(...)`. The header
      // declares the selector `updateTravelEstimates:forManeuver:`, but
      // CarPlay.apinotes renames it for Swift:
      //
      //   Selector:  'updateTravelEstimates:forManeuver:'
      //   SwiftName: 'updateEstimates(_:for:)'
      //
      // Reading the header alone got this wrong twice. The apinotes file is
      // where a framework's Swift spelling actually lives.
      //
      // The time is *not* zero, which is what shipped and what made the car show
      // an arrival time of the current clock on every update (#452).
      // CPTravelEstimates.h:
      //
      //   A distance value less than 0 or a time remaining value less than 0 will
      //   render as "--" […] Values less than 0 are distinguished from distance or
      //   time values equal to 0; your app may display 0 as the user is imminently
      //   arriving at their destination.
      //
      // So zero says "arriving now". Negative is the documented way to say
      // "unavailable". The estimate itself is computed on the Dart side, where its
      // edge cases — no speed, stopped at lights, a nonsense fix — are reachable
      // in a test rather than only by riding.
      let secondsRemaining =
        (snapshot["guidanceSecondsRemaining"] as? NSNumber)?.doubleValue ?? -1
      navigationSession.updateEstimates(
        CPTravelEstimates(
          distanceRemaining: remaining,
          timeRemaining: secondsRemaining
        ),
        for: maneuver
      )
    }
    if #available(iOS 17.4, *) {
      navigationSession.currentRoadNameVariants = roadName.map { [$0] } ?? []
    }
  }

  private func markerSymbol(for stage: String?) -> UIImage? {
    switch stage {
    case "tecApproaching": return navigationSymbol(named: "shield.lefthalf.filled")
    case "readyToRideOff": return navigationSymbol(named: "play.fill")
    default: return navigationSymbol(named: "arrow.triangle.branch")
    }
  }

  @available(iOS 17.4, *)
  private func maneuverType(for title: String) -> CPManeuverType {
    let lowercased = title.lowercased()
    if lowercased.contains("keep left") { return .keepLeft }
    if lowercased.contains("keep right") { return .keepRight }
    if lowercased.contains("slight left") { return .slightLeftTurn }
    if lowercased.contains("slight right") { return .slightRightTurn }
    if lowercased.contains("destination") || lowercased.contains("arrive") {
      return .arriveAtDestination
    }
    // Roundabout before left/right (#447). "Roundabout, 2nd exit, right" matched
    // `right` first and was handed to the cluster as a plain right turn, so the
    // car drew a different junction from the phone.
    if lowercased.contains("roundabout") { return .enterRoundabout }
    if lowercased.contains("left") { return .leftTurn }
    if lowercased.contains("right") { return .rightTurn }
    if lowercased.contains("u-turn") || lowercased.contains("uturn") {
      return .uTurn
    }
    return .straightAhead
  }

  private func recenterButton() -> CPMapButton {
    let button = CPMapButton { [weak self] _ in
      self?.mapViewController?.recenter()
    }
    button.image = mapButtonImage(
      // The phone's landscape control uses an outlined navigation arrow.
      named: "location.north",
      color: CarPlayPalette.actionInk,
      accessibilityLabel: "Follow my location"
    )
    return button
  }

  private func updateSurfaceActions(_ snapshot: [String: Any]) {
    surfaceMode = nonEmptyString(snapshot["surfaceMode"]) ?? "unavailable"
    canPlanRoute = (snapshot["canPlanRoute"] as? NSNumber)?.boolValue ?? false
    canFreeRoam = (snapshot["canFreeRoam"] as? NSNumber)?.boolValue ?? false
    mapOrientation = snapshot["mapOrientation"] as? String == "northUp"
      ? "northUp"
      : "directionUp"
    voiceMuted = (snapshot["voiceMuted"] as? NSNumber)?.boolValue ?? true
    guard let mapTemplate else { return }

    // Active-ride actions are app-owned buttons on the map canvas, matching the
    // phone's labelled ALERT/REPORT controls. The generic follow, browse and
    // blue template buttons duplicated those actions and obscured the road.
    // Route entry remains a template interaction on the stationary home map.
    var buttons: [CPMapButton] = []
    if surfaceMode == "activeRide" {
      buttons.append(mapOrientationButton())
      buttons.append(voiceMuteButton())
    } else {
      if canPlanRoute { buttons.append(planRouteButton()) }
      if canFreeRoam { buttons.append(freeRoamButton()) }
    }
    mapTemplate.mapButtons = buttons
  }

  private func mapOrientationButton() -> CPMapButton {
    let button = CPMapButton { _ in
      (UIApplication.shared.delegate as? AppDelegate)?.toggleCarPlayMapOrientation()
    }
    let northUp = mapOrientation == "northUp"
    button.image = mapButtonImage(
      named: northUp ? "location.north.fill" : "location.north.line.fill",
      color: CarPlayPalette.actionInk,
      accessibilityLabel: northUp
        ? "North-up map. Switch to direction-up"
        : "Direction-up map. Switch to north-up"
    )
    return button
  }

  private func voiceMuteButton() -> CPMapButton {
    let button = CPMapButton { _ in
      (UIApplication.shared.delegate as? AppDelegate)?.toggleCarPlayVoiceMute()
    }
    button.image = mapButtonImage(
      named: voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
      color: CarPlayPalette.actionInk,
      accessibilityLabel: voiceMuted
        ? "Voice muted. Turn voice on"
        : "Voice on. Mute and stop voice"
    )
    return button
  }

  private func planRouteButton() -> CPMapButton {
    let button = CPMapButton { [weak self] _ in
      self?.presentDestinationSearch()
    }
    button.image = mapButtonImage(
      named: "magnifyingglass",
      color: CarPlayPalette.actionInk,
      accessibilityLabel: "Plan a destination"
    )
    return button
  }

  private func freeRoamButton() -> CPMapButton {
    let button = CPMapButton { [weak self] _ in
      self?.presentFreeRoamConfirmation()
    }
    // `road.lanes` is the closest SF Symbol to Flutter's add-road icon on the
    // phone home bar. It remains recognisable on iOS 16+ CarPlay displays.
    button.image = mapButtonImage(
      named: "road.lanes",
      color: CarPlayPalette.routeAhead,
      accessibilityLabel: "Start free roam"
    )
    return button
  }

  private func panButton(mapTemplate: CPMapTemplate) -> CPMapButton {
    let button = CPMapButton { _ in
      mapTemplate.showPanningInterface(animated: true)
    }
    button.image = mapButtonImage(
      named: "arrow.up.and.down.and.arrow.left.and.right",
      color: CarPlayPalette.actionInk,
      accessibilityLabel: "Pan map"
    )
    return button
  }

  private func reportButton() -> CPMapButton {
    let button = CPMapButton { [weak self] _ in
      self?.presentReportActions()
    }
    button.image = mapButtonImage(
      named: "bell.badge.fill",
      color: CarPlayPalette.reportAccent,
      accessibilityLabel: "Report alert"
    )
    return button
  }

  private func emergencyButton() -> CPMapButton {
    let button = CPMapButton { [weak self] _ in
      self?.presentEmergencyConfirmation()
    }
    button.image = mapButtonImage(
      // CPMapButton supplies the circular target already. The bare SOS glyph
      // matches the phone and avoids the double-circle visible on the head unit.
      named: "sos",
      color: CarPlayPalette.emergencyFill,
      accessibilityLabel: "SOS"
    )
    return button
  }

  /// Uses the same glyph colour language as the phone's landscape action row.
  /// `CPMapButton` supplies CarPlay's system-sized target; preserving the
  /// symbol's original colour keeps REPORT yellow and SOS red instead of
  /// flattening every action into the same blue control.
  private func mapButtonImage(
    named systemName: String,
    color: UIColor,
    accessibilityLabel: String
  ) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
    let image = UIImage(systemName: systemName, withConfiguration: configuration)?
      .withTintColor(color, renderingMode: .alwaysOriginal)
    image?.accessibilityLabel = accessibilityLabel
    return image
  }

  private func presentDestinationSearch() {
    guard
      sceneLifecycle.rootReady,
      canPlanRoute,
      let interfaceController
    else { return }
    submittedSearchText = ""
    let search = CPSearchTemplate()
    search.delegate = self
    interfaceController.pushTemplate(search, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay destination search was not presented: %@", error.localizedDescription)
      }
    }
  }

  func searchTemplate(
    _ searchTemplate: CPSearchTemplate,
    updatedSearchText searchText: String,
    completionHandler: @escaping ([CPListItem]) -> Void
  ) {
    // The phone's public Nominatim integration explicitly forbids
    // autocomplete. Keep the typed value locally and perform one request only
    // when Search is submitted.
    submittedSearchText = searchText
    completionHandler([])
  }

  func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
    let query = submittedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      presentCarPlayError("Enter a destination.")
      return
    }
    (UIApplication.shared.delegate as? AppDelegate)?
      .searchCarPlayDestinations(query: query) { [weak self, weak searchTemplate] response in
        DispatchQueue.main.async {
          guard let self, let searchTemplate else { return }
          self.presentDestinationResults(response, from: searchTemplate)
        }
      }
  }

  func searchTemplate(
    _ searchTemplate: CPSearchTemplate,
    selectedResult item: CPListItem,
    completionHandler: @escaping () -> Void
  ) {
    completionHandler()
    guard let destination = item.userInfo as? [String: Any] else { return }
    presentDestinationChoice(destination)
  }

  private func presentDestinationResults(
    _ response: [String: Any],
    from searchTemplate: CPSearchTemplate
  ) {
    guard
      sceneLifecycle.rootReady,
      let interfaceController,
      interfaceController.topTemplate === searchTemplate
    else { return }
    if let error = nonEmptyString(response["error"]) {
      presentCarPlayError(error)
      return
    }
    let destinations = response["results"] as? [[String: Any]] ?? []
    guard !destinations.isEmpty else {
      presentCarPlayError("No destinations matched that search.")
      return
    }
    let items = destinations.prefix(5).compactMap { destination -> CPListItem? in
      guard let label = nonEmptyString(destination["label"]) else { return nil }
      let title = label.split(separator: ",", maxSplits: 1)
        .first.map(String.init) ?? label
      let item = CPListItem(text: title, detailText: label)
      item.userInfo = destination
      item.handler = { [weak self] _, completion in
        completion()
        self?.presentDestinationChoice(destination)
      }
      return item
    }
    let results = CPListTemplate(
      title: "Choose destination",
      sections: [CPListSection(items: items)]
    )
    interfaceController.pushTemplate(results, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay destination results were not presented: %@", error.localizedDescription)
      }
    }
  }

  private func presentDestinationChoice(_ destination: [String: Any]) {
    guard
      sceneLifecycle.rootReady,
      let interfaceController,
      let label = nonEmptyString(destination["label"])
    else { return }
    let shortLabel = label.split(separator: ",", maxSplits: 1)
      .first.map(String.init) ?? label
    let actions: [CPAlertAction]
    if surfaceMode == "home" {
      actions = [
        CPAlertAction(title: "Drive solo", style: .default) { [weak self] _ in
          self?.requestDestinationPlan(destination, groupRide: false)
        },
        CPAlertAction(title: "Create crew flight", style: .default) { [weak self] _ in
          self?.requestDestinationPlan(destination, groupRide: true)
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true, completion: nil)
        },
      ]
    } else {
      actions = [
        CPAlertAction(title: "Use this route", style: .default) { [weak self] _ in
          self?.requestDestinationPlan(destination, groupRide: nil)
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true, completion: nil)
        },
      ]
    }
    let sheet = CPActionSheetTemplate(
      title: "Route to \(shortLabel)?",
      message: label,
      actions: actions
    )
    interfaceController.presentTemplate(sheet, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay destination choice was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func requestDestinationPlan(
    _ destination: [String: Any],
    groupRide: Bool?
  ) {
    guard
      let interfaceController,
      let label = nonEmptyString(destination["label"]),
      let latitude = (destination["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (destination["longitude"] as? NSNumber)?.doubleValue
    else { return }
    interfaceController.dismissTemplate(animated: true) { [weak self] _, _ in
      guard let self else { return }
      interfaceController.popToRootTemplate(animated: true) { _, _ in
        (UIApplication.shared.delegate as? AppDelegate)?.planCarPlayDestination(
          label: label,
          latitude: latitude,
          longitude: longitude,
          groupRide: groupRide
        ) { [weak self] success, error in
          guard !success else { return }
          DispatchQueue.main.async {
            self?.presentCarPlayError(error ?? "Could not plan that route.")
          }
        }
      }
    }
  }

  private func presentFreeRoamConfirmation() {
    guard
      sceneLifecycle.rootReady,
      canFreeRoam,
      let interfaceController
    else { return }
    let sheet = CPActionSheetTemplate(
      title: "Start free roam?",
      message: "Starts a recovery session with no planned road route. Your track is still recorded.",
      actions: [
        CPAlertAction(title: "Start free roam", style: .default) { [weak self] _ in
          interfaceController.dismissTemplate(animated: true) { _, _ in
            (UIApplication.shared.delegate as? AppDelegate)?
              .startFreeRoamFromCarPlay { [weak self] success, error in
                guard !success else { return }
                DispatchQueue.main.async {
                  self?.presentCarPlayError(error ?? "Could not start free roam.")
                }
              }
          }
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true, completion: nil)
        },
      ]
    )
    interfaceController.presentTemplate(sheet, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay free-roam confirmation was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func presentCarPlayError(_ message: String) {
    guard sceneLifecycle.rootReady, let interfaceController else { return }
    let alert = CPAlertTemplate(
      titleVariants: [message, "Action unavailable"],
      actions: [
        CPAlertAction(title: "OK", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true, completion: nil)
        },
      ]
    )
    interfaceController.presentTemplate(alert, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay error alert was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func statusButton(
    interfaceController: CPInterfaceController,
    template: CPListTemplate
  ) -> CPBarButton {
    // Mirror the phone's compact landscape hamburger instead of allowing the
    // word "Ride" to expand into the largest control in the navigation bar.
    let image = mapButtonImage(
      named: "line.3.horizontal",
      color: CarPlayPalette.actionInk,
      accessibilityLabel: "Flight actions"
    ) ?? UIImage()
    return CPBarButton(image: image) { [weak self, weak interfaceController] _ in
      guard
        let self,
        self.sceneLifecycle.rootReady,
        let interfaceController,
        self.interfaceController === interfaceController
      else { return }
      interfaceController.pushTemplate(template, animated: true) { success, error in
        if !success, let error {
          NSLog("CarPlay flight status was not presented: %@", error.localizedDescription)
        }
      }
    }
  }

  /// Projects only the last pre-departure decision. Creation, joining, route
  /// selection and first-time permissions stay on the phone; Dart does not send
  /// this block unless the local rider owns a prepared, unstarted session.
  private func updateRideStart(_ prompt: [String: Any]?) {
    rideStartPrompt = prompt
    updateLeadingNavigationButtons()
  }

  private func updateLeadingNavigationButtons() {
    guard
      let mapTemplate,
      let rideMenuButton,
      !isShowingPanningInterface
    else { return }
    let enabled = (rideStartPrompt?["enabled"] as? NSNumber)?.boolValue ?? false
    mapTemplate.leadingNavigationBarButtons = enabled
      ? [rideMenuButton, startRideButton()]
      : [rideMenuButton]
  }

  private func startRideButton() -> CPBarButton {
    CPBarButton(title: "Start") { [weak self] _ in
      self?.presentStartRideConfirmation()
    }
  }

  private func presentStartRideConfirmation() {
    guard
      sceneLifecycle.rootReady,
      let interfaceController,
      let prompt = rideStartPrompt,
      (prompt["enabled"] as? NSNumber)?.boolValue == true
    else { return }

    let detail = nonEmptyString(prompt["detail"])
    let warning = nonEmptyString(prompt["warning"])
    let message = [detail, warning].compactMap { $0 }.joined(separator: "\n\n")
    let sheet = CPActionSheetTemplate(
      title: "Start prepared flight?",
      message: message.isEmpty ? nil : message,
      actions: [
        CPAlertAction(title: "Start flight", style: .default) { [weak self] _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay start sheet could not be dismissed: %@", error.localizedDescription)
            }
          }
          // Hide the action immediately. Dart will either publish the active
          // ride or re-offer it if revalidation rejects the stale snapshot.
          self?.rideStartPrompt = nil
          self?.updateLeadingNavigationButtons()
          (UIApplication.shared.delegate as? AppDelegate)?.startPreparedRideFromCarPlay()
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay start sheet could not be dismissed: %@", error.localizedDescription)
            }
          }
        },
      ]
    )
    interfaceController.presentTemplate(sheet, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay start sheet was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func presentReportActions() {
    guard sceneLifecycle.rootReady, let interfaceController else { return }
    let report: (String) -> Void = { type in
      interfaceController.dismissTemplate(animated: true) { _, error in
        if let error {
          NSLog("CarPlay report sheet could not be dismissed: %@", error.localizedDescription)
        }
      }
      (UIApplication.shared.delegate as? AppDelegate)?
        .reportCarPlayHazard(type: type)
    }
    let sheet = CPActionSheetTemplate(
      title: "Report to group",
      message: "Uses your current position",
      actions: [
        CPAlertAction(title: "Road hazard", style: .default) { _ in
          report("other")
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay report sheet could not be dismissed: %@", error.localizedDescription)
            }
          }
        },
      ]
    )
    interfaceController.presentTemplate(sheet, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay report sheet was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func presentEmergencyConfirmation() {
    guard sceneLifecycle.rootReady, let interfaceController else { return }
    let alert = CPAlertTemplate(
      titleVariants: ["Send SOS to the group?", "Send SOS?"],
      actions: [
        CPAlertAction(title: "Send SOS", style: .destructive) { _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay SOS alert could not be dismissed: %@", error.localizedDescription)
            }
          }
          (UIApplication.shared.delegate as? AppDelegate)?.triggerCarPlayEmergency()
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay SOS alert could not be dismissed: %@", error.localizedDescription)
            }
          }
        },
      ]
    )
    interfaceController.presentTemplate(alert, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay SOS alert was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func presentLeaveConfirmation() {
    guard sceneLifecycle.rootReady, let interfaceController else { return }
    let sheet = CPActionSheetTemplate(
      title: "Leave this flight?",
      message: "Stops sharing this crew device's position and returns the phone and CarPlay to the home map.",
      actions: [
        CPAlertAction(title: "Leave flight", style: .destructive) { _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay leave sheet could not be dismissed: %@", error.localizedDescription)
            }
          }
          (UIApplication.shared.delegate as? AppDelegate)?.leaveRideFromCarPlay()
        },
        CPAlertAction(title: "Cancel", style: .cancel) { _ in
          interfaceController.dismissTemplate(animated: true) { _, error in
            if let error {
              NSLog("CarPlay leave sheet could not be dismissed: %@", error.localizedDescription)
            }
          }
        },
      ]
    )
    interfaceController.presentTemplate(sheet, animated: true) { success, error in
      if !success, let error {
        NSLog("CarPlay leave sheet was not presented: %@", error.localizedDescription)
      }
    }
  }

  private func coordinate(from raw: [String: Any]?) -> CLLocationCoordinate2D? {
    guard
      let raw,
      let latitude = (raw["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (raw["longitude"] as? NSNumber)?.doubleValue,
      (-90 ... 90).contains(latitude),
      (-180 ... 180).contains(longitude)
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  private func nonEmptyString(_ raw: Any?) -> String? {
    guard let value = raw as? String, !value.isEmpty else { return nil }
    return value
  }

  private func maneuverSymbol(for title: String) -> UIImage? {
    let lowercased = title.lowercased()
    if lowercased.contains("keep left") || lowercased.contains("slight left") {
      return navigationSymbol(named: "arrow.up.left")
    }
    if lowercased.contains("keep right") || lowercased.contains("slight right") {
      return navigationSymbol(named: "arrow.up.right")
    }
    if lowercased.contains("destination") || lowercased.contains("arrive") {
      return navigationSymbol(named: "flag.checkered")
    }
    if lowercased.contains("left") {
      return navigationSymbol(named: "arrow.turn.up.left")
    }
    if lowercased.contains("right") {
      return navigationSymbol(named: "arrow.turn.up.right")
    }
    if lowercased.contains("roundabout") {
      return navigationSymbol(named: "arrow.clockwise.circle")
    }
    if lowercased.contains("u-turn") || lowercased.contains("uturn") {
      return navigationSymbol(named: "arrow.uturn.up")
    }
    return navigationSymbol(named: "arrow.up")
  }

  private func navigationSymbol(named name: String) -> UIImage? {
    UIImage(
      systemName: name,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
    )
  }
}
/// The app's own map palette, mirrored for the CarPlay canvas.
///
/// Every value here is `RouteTrailStyle` in
/// `apps/mobile/lib/features/map/route_trail_style.dart`, and the reasoning for
/// each lives there rather than being restated: these are measured contrast
/// choices from #107, #133 and #143, not decoration. System colours were used
/// while the canvas was being stood up and were wrong on every count — the
/// route was `systemYellow`, which #107 rejected outright because it disappears
/// into the `#FFEEAA` trunk-road fill it is drawn on.
///
/// Two in particular are easy to "correct" back into a bug:
///
/// * **Glyph ink is dark, not white.** Every badge fill is deliberately light so
///   it can be found on a dark basemap, which makes a white glyph the one ink on
///   the map with nothing behind it — 1.53:1 on caution yellow. Dark reverses it
///   to 4.74:1 at worst.
/// * **Every line gets an opaque casing under it.** The casing is what keeps a
///   route readable where it crosses a light road fill.
private enum CarPlayPalette {
  static let casing = UIColor(red: 0x10 / 255, green: 0x15 / 255, blue: 0x1C / 255, alpha: 1)
  static let markerGlyph = casing
  static let routeAhead = UIColor(red: 0x3D / 255, green: 0xDC / 255, blue: 0x84 / 255, alpha: 1)
  static let ownRider = UIColor(red: 0x2F / 255, green: 0x80 / 255, blue: 0xED / 255, alpha: 1)
  static let balloonBlue = UIColor(red: 0x68 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1)
  static let rider = UIColor(red: 0x6E / 255, green: 0xD8 / 255, blue: 0x9A / 255, alpha: 1)
  static let alerting = UIColor(red: 0xFF / 255, green: 0x5D / 255, blue: 0x73 / 255, alpha: 1)

  /// The recovery chrome's card fill and label ink, matching the phone.
  static let cardFill = UIColor(red: 0x25 / 255, green: 0x2E / 255, blue: 0x39 / 255, alpha: 0.90)
  static let primaryPanelFill = UIColor(
    red: 0x25 / 255,
    green: 0x2E / 255,
    blue: 0x39 / 255,
    alpha: 0.85
  )
  static let cardLabel = UIColor(red: 0xB7 / 255, green: 0xC2 / 255, blue: 0xCF / 255, alpha: 1)
  static let cardTitle = UIColor.white
  static let actionInk = UIColor(red: 0xE4 / 255, green: 0xE9 / 255, blue: 0xEF / 255, alpha: 1)
  static let reportAccent = UIColor(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x4A / 255, alpha: 1)
  static let emergencyFill = UIColor(red: 0xD9 / 255, green: 0x30 / 255, blue: 0x4F / 255, alpha: 1)
  static let leaveFill = UIColor(red: 0x54 / 255, green: 0x5F / 255, blue: 0x6E / 255, alpha: 1)

  /// `RouteLineStyle.routeAhead`: 6pt line on a 10pt casing.
  static let routeWidth: CGFloat = 6
  static let routeCasingWidth: CGFloat = 10

}

/// Draws app-owned route and group-location content behind the CarPlay
/// templates. CarPlay owns the turn cards and controls; this owns only the map
/// canvas.
///
/// MapLibre, not MapKit (#321). The head unit shares the phone's MapLibre style
/// and its ambient tile cache — same process, same cache — so a rider who loses
/// signal keeps the basemap they had a mile ago instead of watching the car
/// screen go grey, and the deliberate day/night styling measured in #107 and
/// #143 reaches the surface a rider actually looks at while moving.
private final class CarPlayNavigationViewController: UIViewController,
  MLNMapViewDelegate
{
  private var mapView: MLNMapView?
  private let speedBadge = CarPlaySpeedLimitBadge()
  private let compassBadge = CarPlayCompassBadge()
  private let groupMiniMap = CarPlayGroupMiniMapView()
  private let navigationPane = UILayoutGuide()
  private let clockLabel = CarPlayClockLabel()
  private let guidanceView = CarPlayGuidanceView()
  private let rideActionsView = CarPlayRideActionsView()
  private var routeSource: MLNShapeSource?
  private var sharedTraceSources: [String: MLNShapeSource] = [:]
  private var routeCoordinates: [CLLocationCoordinate2D] = []
  private var routeID: String?
  private var routeProjectionKey: String?
  private var riderAnnotations: [CarPlayRiderAnnotation] = []
  private var localCoordinate: CLLocationCoordinate2D?
  private var localHeading: CLLocationDirection?
  private var followsLocalRider = true
  private var snapshotWantsRiderFollow = false
  private var mapOrientation = "directionUp"
  private var panGestureStartCoordinate: CLLocationCoordinate2D?
  private var hasFramedFirstFix = false
  private var surfaceMode = "unavailable"

  var onReport: (() -> Void)?
  var onEmergency: (() -> Void)?
  var onLeave: (() -> Void)?

  /// The styles Dart published, the exact style selected on the phone, and the
  /// one currently applied. CarPlay's trait remains a fallback until Dart has
  /// supplied the phone selection; after that both screens change together.
  private var lightStyleURL: URL?
  private var darkStyleURL: URL?
  private var appliedStyleURL: URL?
  private var phoneStyleURL: URL?
  private var phoneStyleJSON: String?
  private var appliedStyleJSON: String?

  /// The last snapshot, replayed once the style finishes loading. A style load
  /// clears every annotation with it, so route and riders have to go back on
  /// afterwards or the map comes back empty (#295 by a different route).
  private var latestSnapshot: [String: Any]?
  private var latestViewport: [String: Any]?

  /// Used only until Dart's first snapshot names a style, which it does on the
  /// first ride-state change. Without it a rider who plugs in before starting a
  /// ride gets a black rectangle — #295 all over again, since the projected
  /// snapshot is published from the ride shell and there is nothing to publish
  /// before a ride. Kept in step with `BasemapConfiguration`'s own defaults;
  /// Dart's value always wins the moment it arrives.
  private static let fallbackStyleURLs = (
    light: URL(string: "https://tiles.openfreemap.org/styles/liberty"),
    dark: URL(string: "https://tiles.openfreemap.org/styles/dark")
  )

  override func loadView() {
    // A plain view first: MLNMapView with no style URL renders nothing useful
    // and does not restyle cleanly afterwards, so the map is installed once a
    // style is known — from Dart if it has published one, otherwise the
    // fallback, so the canvas is never blank.
    let container = UIView(frame: .zero)
    container.backgroundColor = .black
    view = container
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    guard lightStyleURL == nil, darkStyleURL == nil else { return }
    lightStyleURL = Self.fallbackStyleURLs.light
    darkStyleURL = Self.fallbackStyleURLs.dark
    applyPreferredStyle()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // The left pane is a complete north-up group map. The live road-navigation
    // map remains on the right and uses a separate camera anchor, so neither
    // surface has to compromise the other one's orientation or framing.
    view.addLayoutGuide(navigationPane)
    speedBadge.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(speedBadge)
    compassBadge.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(compassBadge)
    groupMiniMap.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(groupMiniMap)
    // The clock (#452), drawn by the app. Apple's own widget was ruled out
    // explicitly: it carries its own styling and placement and would not sit with
    // the badges either side of it.
    clockLabel.translatesAutoresizingMaskIntoConstraints = false
    clockLabel.isHidden = true
    view.addSubview(clockLabel)
    guidanceView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(guidanceView)
    rideActionsView.translatesAutoresizingMaskIntoConstraints = false
    rideActionsView.onFollow = { [weak self] in self?.recenter() }
    rideActionsView.onReport = { [weak self] in self?.onReport?() }
    rideActionsView.onEmergency = { [weak self] in self?.onEmergency?() }
    rideActionsView.onLeave = { [weak self] in self?.onLeave?() }
    view.addSubview(rideActionsView)
    NSLayoutConstraint.activate([
      // Keep the speed pair where riders already expect it.
      speedBadge.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -52
      ),
      speedBadge.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 10
      ),
      // One visual unit: the compass circle is exactly the sign's 34-point
      // diameter and sits eight points immediately to its left.
      compassBadge.widthAnchor.constraint(equalToConstant: 34),
      compassBadge.heightAnchor.constraint(equalToConstant: 34),
      compassBadge.trailingAnchor.constraint(
        equalTo: speedBadge.leadingAnchor,
        constant: -3
      ),
      compassBadge.topAnchor.constraint(equalTo: speedBadge.topAnchor),
      // A real second map pane, not the old 196-point mini-map card.
      groupMiniMap.widthAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.widthAnchor,
        multiplier: 0.44
      ),
      groupMiniMap.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor
      ),
      groupMiniMap.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 4
      ),
      groupMiniMap.bottomAnchor.constraint(
        equalTo: view.bottomAnchor,
        constant: -4
      ),
      navigationPane.leadingAnchor.constraint(
        equalTo: groupMiniMap.trailingAnchor,
        constant: 4
      ),
      navigationPane.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor
      ),
      navigationPane.topAnchor.constraint(equalTo: view.topAnchor),
      navigationPane.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      // Centre the clock over the road-navigation pane, not over the divider.
      clockLabel.centerXAnchor.constraint(
        equalTo: navigationPane.centerXAnchor
      ),
      clockLabel.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 12
      ),
      guidanceView.trailingAnchor.constraint(
        equalTo: navigationPane.trailingAnchor,
        constant: -12
      ),
      guidanceView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor,
        constant: -12
      ),
      guidanceView.widthAnchor.constraint(
        equalTo: navigationPane.widthAnchor,
        multiplier: 0.66
      ),
      guidanceView.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
      rideActionsView.leadingAnchor.constraint(
        equalTo: navigationPane.leadingAnchor,
        constant: 8
      ),
      rideActionsView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor,
        constant: -12
      ),
    ])
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    guard
      traitCollection.userInterfaceStyle != previous?.userInterfaceStyle
    else { return }
    applyPreferredStyle()
  }

  func apply(snapshot: [String: Any]) {
    latestSnapshot = snapshot
    mapOrientation = snapshot["mapOrientation"] as? String == "northUp"
      ? "northUp"
      : "directionUp"
    updateStyleURLs(snapshot["basemap"] as? [String: Any])
    guard let mapView else { return }
    surfaceMode = snapshot["surfaceMode"] as? String ?? "activeRide"
    let darkMap =
      ((snapshot["basemap"] as? [String: Any])?["dark"] as? NSNumber)?.boolValue
      ?? (traitCollection.userInterfaceStyle == .dark)
    if surfaceMode != "activeRide" {
      // A viewport belongs to the moving ride that produced it. Replaying it
      // over the home or pre-ride map is what reopened CarPlay miles away from
      // the phone after ending a ride.
      latestViewport = nil
    }
    clockLabel.isHidden = surfaceMode == "home"
    clockLabel.apply(darkMap: darkMap)
    compassBadge.apply(direction: mapView.direction, darkMap: darkMap)
    rideActionsView.isHidden = surfaceMode != "activeRide"
    rideActionsView.setFollowing(followsLocalRider)
    guidanceView.apply(snapshot: snapshot)
    let incomingRouteID = snapshot["routeId"] as? String
    let progress = (snapshot["routeProgressMeters"] as? NSNumber)?.doubleValue ?? 0
    let routeKey = "\(incomingRouteID ?? "none"):\(Int(progress / 2))"
    let routeChanged =
      routeKey != routeProjectionKey
      || routeSource == nil
    if routeChanged {
      updateRoute(
        snapshot["routePoints"],
        remaining: snapshot["remainingRoutePoints"]
      )
      routeID = incomingRouteID
      routeProjectionKey = routeKey
    }
    updateSharedTraces(snapshot["sharedTraces"])
    updateRiders(snapshot)
    if surfaceMode == "home" {
      groupMiniMap.isHidden = true
    } else {
      groupMiniMap.apply(
        snapshot: snapshot,
        styleURL: preferredStyleURL,
        styleJSON: phoneStyleJSON
      )
    }
    speedBadge.apply(snapshot["speed"] as? [String: Any])
    let requestedRiderFollow =
      (snapshot["followRider"] as? NSNumber)?.boolValue ?? false
    let cameraModeChanged = requestedRiderFollow != snapshotWantsRiderFollow
    snapshotWantsRiderFollow = requestedRiderFollow
    if cameraModeChanged {
      // A ride starting is the one automatic transition back into follow mode.
      // Subsequent snapshots preserve a deliberate pan until the rider taps
      // recenter, while waiting-to-start remains a route overview like the
      // phone map.
      followsLocalRider = requestedRiderFollow
    }
    rideActionsView.setFollowing(followsLocalRider)
    // The ride's own marker carries the exact identity symbol and colour the
    // rider chose on the phone. Do not replace it with MapLibre's unrelated
    // blue location dot while snapshots settle.
    mapView.showsUserLocation = false
    if requestedRiderFollow, localCoordinate != nil, followsLocalRider {
      recenter()
    } else if routeChanged || cameraModeChanged {
      showCompleteRoute()
    }
  }

  /// Applies the camera the phone actually commanded, rather than independently
  /// planning a second navigation camera on the head unit. The target already
  /// includes the phone's look-ahead; only the zoom is adjusted for CarPlay's
  /// different viewport height so both screens cover the same ground distance.
  func apply(viewport: [String: Any]) {
    latestViewport = viewport
    if
      let rawStyleURL = viewport["mapStyleUrl"] as? String,
      let styleURL = URL(string: rawStyleURL)
    {
      phoneStyleURL = styleURL
      applyPreferredStyle()
    }
    guard
      surfaceMode == "activeRide",
      snapshotWantsRiderFollow,
      followsLocalRider
    else { return }
    applyPhoneViewport(animated: true)
  }

  /// Uses the resolved style document from the phone, not another fetch of the
  /// URL it originally came from. The phone may be rendering a normalised,
  /// cached or dark-mode-repainted document, so loading the URL again can give
  /// CarPlay visibly different roads, labels and tiles.
  func apply(mapStyle: [String: Any]) {
    guard
      let styleJSON = mapStyle["styleJson"] as? String,
      !styleJSON.isEmpty
    else { return }
    phoneStyleJSON = styleJSON
    if
      let rawURL = mapStyle["fallbackStyleUrl"] as? String,
      let fallbackURL = URL(string: rawURL)
    {
      phoneStyleURL = fallbackURL
    }
    applyPreferredStyle()
    if
      let latestSnapshot,
      latestSnapshot["surfaceMode"] as? String != "home"
    {
      groupMiniMap.apply(
        snapshot: latestSnapshot,
        styleURL: preferredStyleURL,
        styleJSON: phoneStyleJSON,
        force: true
      )
    }
  }

  func recenter() {
    followsLocalRider = true
    rideActionsView.setFollowing(true)
    if snapshotWantsRiderFollow, latestViewport != nil {
      applyPhoneViewport(animated: true)
      return
    }
    guard let mapView else { return }
    guard let coordinate = localCoordinate else {
      showCompleteRoute()
      return
    }
    if surfaceMode == "home" {
      mapView.userTrackingMode = .none
      mapView.setCenter(coordinate, zoomLevel: 14, animated: true)
      return
    }
    // Taking the camera back off MapLibre's follow mode, or it animates against
    // every camera this sets. The ride's own fix is preferred once there is one:
    // it carries the rider's heading and is the position the rest of the group
    // is being measured against.
    mapView.userTrackingMode = .none
    let camera = MLNMapCamera(
      lookingAtCenter: coordinate,
      altitude: 1_800,
      pitch: 25,
      heading: localHeading ?? 0
    )
    mapView.setCamera(camera, animated: true)
  }

  func pan(direction: CPMapTemplate.PanDirection) {
    followsLocalRider = false
    rideActionsView.setFollowing(false)
    guard let mapView else { return }
    mapView.userTrackingMode = .none
    var point = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
    let step = CGPoint(x: mapView.bounds.width * 0.25, y: mapView.bounds.height * 0.25)
    if direction.contains(.left) { point.x -= step.x }
    if direction.contains(.right) { point.x += step.x }
    if direction.contains(.up) { point.y -= step.y }
    if direction.contains(.down) { point.y += step.y }
    mapView.setCenter(
      mapView.convert(point, toCoordinateFrom: mapView),
      animated: true
    )
  }

  func beginPanGesture() {
    followsLocalRider = false
    rideActionsView.setFollowing(false)
    mapView?.userTrackingMode = .none
    panGestureStartCoordinate = mapView?.centerCoordinate
  }

  func updatePanGesture(translation: CGPoint) {
    guard let mapView, let start = panGestureStartCoordinate else { return }
    let startPoint = mapView.convert(start, toPointTo: mapView)
    let translated = CGPoint(
      x: startPoint.x - translation.x,
      y: startPoint.y - translation.y
    )
    mapView.setCenter(
      mapView.convert(translated, toCoordinateFrom: mapView),
      animated: false
    )
  }

  func endPanGesture() {
    panGestureStartCoordinate = nil
  }

  // MARK: - Style

  private func updateStyleURLs(_ basemap: [String: Any]?) {
    guard let basemap else { return }
    let light = (basemap["styleUrl"] as? String).flatMap(URL.init(string:))
    let dark = (basemap["darkStyleUrl"] as? String).flatMap(URL.init(string:))
    let selected =
      (basemap["selectedStyleUrl"] as? String).flatMap(URL.init(string:))
    guard light != nil || dark != nil else { return }
    lightStyleURL = light ?? dark
    darkStyleURL = dark ?? light
    phoneStyleURL = selected
    if let styleJSON = basemap["styleJson"] as? String, !styleJSON.isEmpty {
      phoneStyleJSON = styleJSON
    }
    applyPreferredStyle()
  }

  private func applyPreferredStyle() {
    if let preferredJSON = phoneStyleJSON {
      guard preferredJSON != appliedStyleJSON else { return }
      appliedStyleJSON = preferredJSON
      appliedStyleURL = nil
      guard let mapView else {
        installMapView(styleJSON: preferredJSON)
        return
      }
      mapView.styleJSON = preferredJSON
      return
    }
    let preferred = phoneStyleURL
      ?? (traitCollection.userInterfaceStyle == .dark ? darkStyleURL : lightStyleURL)
    guard let preferred, preferred != appliedStyleURL else { return }
    appliedStyleURL = preferred
    appliedStyleJSON = nil
    guard let mapView else {
      installMapView(styleURL: preferred)
      return
    }
    mapView.styleURL = preferred
  }

  private var preferredStyleURL: URL? {
    phoneStyleURL
      ?? (traitCollection.userInterfaceStyle == .dark ? darkStyleURL : lightStyleURL)
  }

  private func installMapView(styleURL: URL) {
    let mapView = MLNMapView(frame: view.bounds, styleURL: styleURL)
    configure(mapView)
  }

  private func installMapView(styleJSON: String) {
    let mapView = MLNMapView(frame: view.bounds, styleJSON: styleJSON)
    configure(mapView)
  }

  private func configure(_ mapView: MLNMapView) {
    mapView.delegate = self
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // The phone's own rider badge is projected below. A second system location
    // dot has different styling and briefly duplicates the rider while the
    // first group snapshot arrives.
    mapView.showsUserLocation = false
    mapView.userTrackingMode = .none
    // The logo goes, as it does on every phone surface (`logoEnabled: false`);
    // the attribution button stays, because that is a licence condition rather
    // than decoration. Keep both MapLibre controls on the right, clear of the
    // app's left-hand status column and the top-trailing speed pair.
    mapView.logoView.isHidden = true
    mapView.attributionButtonPosition = .bottomRight
    mapView.attributionButtonMargins = CGPoint(x: 52, y: 14)
    mapView.compassView.isHidden = true
    // Match the phone home map's no-fix fallback rather than MapLibre's
    // world-sized default. As soon as the phone publishes an authorised fix,
    // the saved rider marker and the same z14 home framing replace this.
    mapView.setCenter(
      CLLocationCoordinate2D(latitude: 54.5, longitude: -3.2),
      zoomLevel: 5,
      animated: false
    )
    view.insertSubview(mapView, at: 0)
    self.mapView = mapView
    if let latestSnapshot { apply(snapshot: latestSnapshot) }
    if let latestViewport { apply(viewport: latestViewport) }
  }

  private func applyPhoneViewport(animated: Bool) {
    guard
      let mapView,
      mapView.bounds.height > 0,
      let viewport = latestViewport,
      let latitude = (viewport["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (viewport["longitude"] as? NSNumber)?.doubleValue,
      let phoneZoom = (viewport["zoom"] as? NSNumber)?.doubleValue,
      let phoneHeight = (viewport["sourceViewportHeightPixels"] as? NSNumber)?.doubleValue,
      let phoneWidth = (viewport["sourceViewportWidthPixels"] as? NSNumber)?.doubleValue,
      phoneHeight > 0,
      phoneWidth > 0,
      latitude.isFinite,
      longitude.isFinite,
      phoneZoom.isFinite,
      (-90 ... 90).contains(latitude),
      (-180 ... 180).contains(longitude)
    else { return }

    let heightRatio = Double(mapView.bounds.height) / phoneHeight
    guard heightRatio.isFinite, heightRatio > 0 else { return }
    let adjustedZoom = phoneZoom + log2(heightRatio)
    let rawTilt = (viewport["tilt"] as? NSNumber)?.doubleValue ?? 0
    let tilt = min(60, max(0, rawTilt))
    let publishedBearing = (viewport["bearing"] as? NSNumber)?.doubleValue ?? 0
    // The left map owns north-up context. Active road navigation is therefore
    // always direction-up, even if the saved phone preference was north-up.
    let bearing = surfaceMode == "activeRide"
      ? (localHeading ?? publishedBearing)
      : (mapOrientation == "northUp" ? 0 : (localHeading ?? publishedBearing))
    let riderVerticalFraction = min(
      0.8,
      max(0.35, (viewport["riderViewportFraction"] as? NSNumber)?.doubleValue ?? 0.64)
    )
    // CarPlay is always landscape even when its attached phone is portrait.
    // A portrait phone publishes a centred phone anchor, so derive the car's
    // traffic-side third from the route handedness instead of copying 0.5.
    let leftHandTraffic =
      (viewport["leftHandTraffic"] as? NSNumber)?.boolValue ?? true
    let riderHorizontalFraction = leftHandTraffic ? (2.0 / 3.0) : (1.0 / 3.0)
    guard adjustedZoom.isFinite, tilt.isFinite, bearing.isFinite else { return }

    // MapLibre's zoom is the scale of 512 px Web Mercator tiles. Convert that
    // scale back to the MLNMapCamera altitude API while preserving the phone's
    // pitch and look-ahead target.
    let latitudeRadians = latitude * .pi / 180
    let metresPerPoint =
      78_271.516_964_020_48 * abs(cos(latitudeRadians)) / pow(2, adjustedZoom)
    let fieldOfView = 0.643_501_108_793_284_4
    let cameraToCenterDistance =
      Double(mapView.bounds.height) * 0.5 / tan(fieldOfView * 0.5)
    let altitude = cameraToCenterDistance * metresPerPoint * cos(tilt * .pi / 180)
    guard altitude.isFinite, altitude > 0 else { return }

    mapView.userTrackingMode = .none
    let camera = MLNMapCamera(
      lookingAtCenter: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: altitude,
      pitch: tilt,
      heading: bearing
    )
    // Establish scale and pitch first, then use MapLibre's own projection to
    // put the local rider at the exact phone anchor on this wider screen. This
    // avoids a fixed-offset approximation and also lifts the marker above the
    // app-owned guidance rail when that rail is taller than the phone's.
    mapView.setCamera(camera, animated: false)
    view.layoutIfNeeded()
    let frame = view.safeAreaLayoutGuide.layoutFrame
    let navigationFrame = navigationPane.layoutFrame
    var desired = CGPoint(
      x: navigationFrame.minX + navigationFrame.width * riderHorizontalFraction,
      y: frame.minY + frame.height * riderVerticalFraction
    )
    // Keep the 18-point-radius rider marker, plus a ten-point visual gap,
    // above the right-hand chrome. The iterative projection below now lands on
    // this anchor exactly, so a larger safety offset would waste road-ahead map.
    let riderChromeClearance: CGFloat = 28
    if !guidanceView.isHidden {
      desired.y = min(
        desired.y,
        guidanceView.frame.minY - riderChromeClearance
      )
    }
    if let localCoordinate {
      var correctedCamera = camera
      // A pitched Mercator projection is not linear in screen Y, so a single
      // centre translation only moved part of the way to the requested anchor
      // on the 1920×720 CarPlay canvas. Reproject after each correction; three
      // small passes converge to the exact open-map point without guessing a
      // latitude-dependent offset.
      for _ in 0 ..< 3 {
        mapView.setCamera(correctedCamera, animated: false)
        let riderPoint = mapView.convert(localCoordinate, toPointTo: mapView)
        let error = CGPoint(
          x: riderPoint.x - desired.x,
          y: riderPoint.y - desired.y
        )
        if hypot(error.x, error.y) < 1 { break }
        let centrePoint = mapView.convert(
          correctedCamera.centerCoordinate,
          toPointTo: mapView
        )
        let correctedCentre = CGPoint(
          x: centrePoint.x + error.x,
          y: centrePoint.y + error.y
        )
        correctedCamera = MLNMapCamera(
          lookingAtCenter: mapView.convert(
            correctedCentre,
            toCoordinateFrom: mapView
          ),
          altitude: altitude,
          pitch: tilt,
          heading: bearing
        )
      }
      // The phone keeps publishing moving fixes, so these small deterministic
      // steps are already continuous. A second UIKit animation here leaves the
      // marker one animation behind and puts it back under the guidance card.
      mapView.setCamera(correctedCamera, animated: false)
    } else {
      mapView.setCamera(camera, animated: animated)
    }
    compassBadge.apply(
      direction: bearing,
      darkMap: ((latestSnapshot?["basemap"] as? [String: Any])?["dark"] as? NSNumber)?
        .boolValue ?? (traitCollection.userInterfaceStyle == .dark)
    )
  }

  /// MapKit's follow mode picks an altitude for you; MapLibre's only recentres
  /// and keeps whatever zoom the map already had. Left alone that framed the
  /// head unit on the whole world and then politely centred the whole world on
  /// the rider. Setting the zoom up front is worse still - with no fix yet the
  /// default centre is null island, so the canvas is featureless grey - so the
  /// driving zoom is taken on the first fix instead, once and only once.
  func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
    guard
      !hasFramedFirstFix,
      let coordinate = userLocation?.location?.coordinate,
      CLLocationCoordinate2DIsValid(coordinate)
    else { return }
    hasFramedFirstFix = true
    guard followsLocalRider, localCoordinate == nil else { return }
    mapView.setCenter(coordinate, zoomLevel: 14, animated: true)
  }

  func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
    // A style load takes the annotations with it. Put the ride back on.
    let previousAnnotations = riderAnnotations.map { $0 as MLNAnnotation }
    if !previousAnnotations.isEmpty {
      // MapLibre normally clears these during the style swap. Removing the
      // retained objects as well closes the short timing window where a
      // snapshot lands between the swap and this callback and would otherwise
      // leave two local-rider badges on the CarPlay map.
      mapView.removeAnnotations(previousAnnotations)
    }
    routeSource = nil
    sharedTraceSources = [:]
    riderAnnotations = []
    routeID = nil
    routeProjectionKey = nil
    if let latestSnapshot { apply(snapshot: latestSnapshot) }
    if let latestViewport { apply(viewport: latestViewport) }
  }

  // MARK: - Content

  private func updateSharedTraces(_ raw: Any?) {
    guard let mapView, let style = mapView.style else { return }
    let traces = raw as? [[String: Any]] ?? []
    var groups: [String: (color: UIColor, width: CGFloat, casing: CGFloat,
      dash: [NSNumber]?, shapes: [MLNPolylineFeature])] = [:]

    for trace in traces {
      guard
        let kind = trace["kind"] as? String,
        let colorArgb = (trace["colorArgb"] as? NSNumber)?.uint32Value,
        let width = (trace["width"] as? NSNumber)?.doubleValue,
        let casing = (trace["casingWidth"] as? NSNumber)?.doubleValue
      else { continue }
      var coordinates = (trace["points"] as? [[String: Any]] ?? [])
        .compactMap(coordinate(from:))
      guard coordinates.count >= 2 else { continue }
      let feature = MLNPolylineFeature(
        coordinates: &coordinates,
        count: UInt(coordinates.count)
      )
      let key = "\(kind)-\(colorArgb)"
      let color = colorFromArgb(colorArgb)
      if var group = groups[key] {
        group.shapes.append(feature)
        groups[key] = group
      } else {
        groups[key] = (
          color: color,
          width: CGFloat(width),
          casing: CGFloat(casing),
          dash: trace["dash"] as? [NSNumber],
          shapes: [feature]
        )
      }
    }

    for (key, source) in sharedTraceSources where groups[key] == nil {
      source.shape = nil
    }
    for (key, group) in groups {
      let identifier = "balloon-crumbs-shared-\(safeStyleIdentifier(key))"
      let source: MLNShapeSource
      if let existing = sharedTraceSources[key] {
        source = existing
      } else if
        let existing = style.source(withIdentifier: identifier) as? MLNShapeSource
      {
        source = existing
        sharedTraceSources[key] = existing
      } else {
        let created = MLNShapeSource(identifier: identifier, shape: nil, options: nil)
        style.addSource(created)
        sharedTraceSources[key] = created
        source = created
      }
      let casingID = "\(identifier)-casing"
      if style.layer(withIdentifier: casingID) == nil {
        let layer = MLNLineStyleLayer(identifier: casingID, source: source)
        layer.lineColor = NSExpression(forConstantValue: CarPlayPalette.casing)
        layer.lineWidth = NSExpression(forConstantValue: group.casing)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.lineJoin = NSExpression(forConstantValue: "round")
        if let dash = group.dash { layer.lineDashPattern = NSExpression(forConstantValue: dash) }
        if let routeLayer = style.layer(withIdentifier: "balloon-crumbs-route-ahead-casing") {
          style.insertLayer(layer, below: routeLayer)
        } else {
          style.addLayer(layer)
        }
      }
      let lineID = "\(identifier)-line"
      if style.layer(withIdentifier: lineID) == nil {
        let layer = MLNLineStyleLayer(identifier: lineID, source: source)
        layer.lineColor = NSExpression(forConstantValue: group.color)
        layer.lineWidth = NSExpression(forConstantValue: group.width)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.lineJoin = NSExpression(forConstantValue: "round")
        if let dash = group.dash { layer.lineDashPattern = NSExpression(forConstantValue: dash) }
        if let routeLayer = style.layer(withIdentifier: "balloon-crumbs-route-ahead-casing") {
          style.insertLayer(layer, below: routeLayer)
        } else {
          style.addLayer(layer)
        }
      }
      source.shape = MLNShapeCollectionFeature(shapes: group.shapes)
    }
  }

  private func colorFromArgb(_ argb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  private func safeStyleIdentifier(_ value: String) -> String {
    value.unicodeScalars.map { String(format: "%02x", $0.value) }.joined()
  }

  private func updateRoute(_ raw: Any?, remaining: Any?) {
    let allPoints = (raw as? [[String: Any]] ?? []).compactMap(coordinate(from:))
    guard allPoints.count >= 2 else {
      routeCoordinates = []
      routeSource?.shape = nil
      return
    }
    routeCoordinates = allPoints
    var remainingPoints =
      (remaining as? [[String: Any]] ?? []).compactMap(coordinate(from:))
    if remainingPoints.count < 2 {
      remainingPoints = allPoints
    }
    updateRemainingRoute(remainingPoints)
  }

  /// The phone's route ahead is a long dash, not a solid line. Shape
  /// annotations have no dash property, so this one part of the route uses two
  /// MapLibre style layers over a shared source: an aligned dashed casing and
  /// the aligned green stroke above it. Completed planned-route geometry is
  /// intentionally omitted so the road immediately behind the rider is map,
  /// matching the phone navigation surface.
  private func updateRemainingRoute(_ points: [CLLocationCoordinate2D]) {
    guard let mapView, let style = mapView.style else { return }
    let sourceIdentifier = "balloon-crumbs-route-ahead-source"
    let casingIdentifier = "balloon-crumbs-route-ahead-casing"
    let lineIdentifier = "balloon-crumbs-route-ahead-line"
    let source: MLNShapeSource
    if let routeSource {
      source = routeSource
    } else if
      let existing = style.source(withIdentifier: sourceIdentifier)
        as? MLNShapeSource
    {
      routeSource = existing
      source = existing
    } else {
      let created = MLNShapeSource(
        identifier: sourceIdentifier,
        shape: nil,
        options: nil
      )
      style.addSource(created)
      routeSource = created
      source = created
    }

    if style.layer(withIdentifier: casingIdentifier) == nil {
      let casing = MLNLineStyleLayer(
        identifier: casingIdentifier,
        source: source
      )
      casing.lineColor = NSExpression(forConstantValue: CarPlayPalette.casing)
      casing.lineWidth = NSExpression(
        forConstantValue: CarPlayPalette.routeCasingWidth
      )
      casing.lineDashPattern = NSExpression(forConstantValue: [2.2, 1.1])
      casing.lineCap = NSExpression(forConstantValue: "round")
      casing.lineJoin = NSExpression(forConstantValue: "round")
      style.addLayer(casing)
    }

    if style.layer(withIdentifier: lineIdentifier) == nil {
      let line = MLNLineStyleLayer(
        identifier: lineIdentifier,
        source: source
      )
      line.lineColor = NSExpression(forConstantValue: CarPlayPalette.routeAhead)
      line.lineWidth = NSExpression(forConstantValue: CarPlayPalette.routeWidth)
      line.lineDashPattern = NSExpression(
        forConstantValue: [22.0 / 6.0, 11.0 / 6.0]
      )
      line.lineCap = NSExpression(forConstantValue: "round")
      line.lineJoin = NSExpression(forConstantValue: "round")
      style.addLayer(line)
    }

    guard points.count >= 2 else {
      source.shape = nil
      return
    }
    var coordinates = points
    source.shape = MLNPolyline(
      coordinates: &coordinates,
      count: UInt(coordinates.count)
    )
  }

  private func updateRiders(_ snapshot: [String: Any]) {
    guard let mapView else { return }
    if !riderAnnotations.isEmpty {
      mapView.removeAnnotations(riderAnnotations)
      riderAnnotations = []
    }
    localCoordinate = nil
    localHeading = nil
    var riders = snapshot["riders"] as? [[String: Any]] ?? []
    if let projectedLocal = snapshot["localRider"] as? [String: Any] {
      let localID = projectedLocal["riderId"] as? String
      if
        let index = riders.firstIndex(where: {
          ($0["riderId"] as? String) == localID
        })
      {
        riders[index].merge(projectedLocal) { _, localValue in localValue }
      } else {
        riders.append(projectedLocal)
      }
    }
    for rider in riders {
      guard let coordinate = coordinate(from: rider) else { continue }
      let isLocal = (rider["isLocal"] as? NSNumber)?.boolValue ?? false
      let annotation = CarPlayRiderAnnotation(
        coordinate: coordinate,
        title: rider["label"] as? String ?? "Craft",
        subtitle: (rider["detail"] as? String) ?? (rider["role"] as? String),
        isLocal: isLocal,
        isTec: (rider["isTec"] as? NSNumber)?.boolValue ?? false,
        needsAttention: (rider["needsAttention"] as? NSNumber)?.boolValue ?? false,
        riderSymbol: rider["riderSymbol"] as? String ?? "craft",
        craftStyle: (rider["craftStyle"] as? String)
          ?? (rider["motorcycleStyle"] as? String)
          ?? "fourByFour",
        riderColor: rider["riderColor"] as? String ?? "green",
        riderColorArgb: (rider["riderColorArgb"] as? NSNumber)?.uint32Value
      )
      riderAnnotations.append(annotation)
      if isLocal {
        localCoordinate = coordinate
        localHeading = (rider["headingDegrees"] as? NSNumber)?.doubleValue
      }
    }
    if
      localCoordinate == nil,
      let projectedPosition = snapshot["localPosition"] as? [String: Any],
      let coordinate = coordinate(from: projectedPosition)
    {
      localCoordinate = coordinate
      localHeading = (projectedPosition["headingDegrees"] as? NSNumber)?.doubleValue
    }
    if !riderAnnotations.isEmpty {
      mapView.addAnnotations(riderAnnotations)
    }
  }

  /// Frames the whole planned route, or - with no route to frame - hands the
  /// camera back to the rider rather than leaving it wherever it was.
  ///
  /// Returning silently with no route is half of #295: a route-less ride
  /// reached here, nothing happened, and the map stayed wherever it had been
  /// left with no way back.
  private func showCompleteRoute() {
    guard let mapView else { return }
    guard routeCoordinates.count >= 2 else {
      mapView.userTrackingMode = .none
      if let localCoordinate {
        mapView.setCenter(localCoordinate, zoomLevel: 14, animated: true)
      }
      return
    }
    mapView.userTrackingMode = .none
    // Fit the route's actual coordinates. `MLNPolyline.overlayBounds` can
    // still report the style's default world-sized bounds while an annotation
    // is being installed during the CarPlay scene's first layout; using it is
    // what reduced a 17.5 km demo route to a tiny mark on a UK-wide map.
    var coordinates = routeCoordinates
    mapView.setVisibleCoordinates(
      &coordinates,
      count: UInt(coordinates.count),
      edgePadding: UIEdgeInsets(
        top: 60,
        left: navigationPane.layoutFrame.minX + 40,
        bottom: 60,
        right: 60
      ),
      animated: true
    )
  }

  private func coordinate(from raw: [String: Any]) -> CLLocationCoordinate2D? {
    guard
      let latitude = (raw["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (raw["longitude"] as? NSNumber)?.doubleValue,
      (-90 ... 90).contains(latitude),
      (-180 ... 180).contains(longitude)
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  func mapView(
    _ mapView: MLNMapView,
    viewFor annotation: MLNAnnotation
  ) -> MLNAnnotationView? {
    guard let rider = annotation as? CarPlayRiderAnnotation else { return nil }
    let reuseID = "CarPlayRider"
    let view =
      mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
      as? CarPlayRiderAnnotationView
      ?? CarPlayRiderAnnotationView(reuseIdentifier: reuseID)
    view.apply(rider)
    return view
  }

  func mapView(
    _ mapView: MLNMapView,
    regionWillChangeWith reason: MLNCameraChangeReason,
    animated: Bool
  ) {
    // MapLibre names the reason, so a rider taking the map over is detected
    // outright rather than inferred from gesture-recogniser state the way the
    // MapKit implementation had to.
    let gestures: MLNCameraChangeReason = [
      .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn,
      .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt,
    ]
    if !reason.intersection(gestures).isEmpty {
      followsLocalRider = false
      rideActionsView.setFollowing(false)
      mapView.userTrackingMode = .none
    }
  }

  func mapViewRegionIsChanging(_ mapView: MLNMapView) {
    let darkMap =
      ((latestSnapshot?["basemap"] as? [String: Any])?["dark"] as? NSNumber)?
      .boolValue ?? (traitCollection.userInterfaceStyle == .dark)
    compassBadge.apply(direction: mapView.direction, darkMap: darkMap)
  }
}

private final class CarPlayRiderAnnotation: NSObject, MLNAnnotation {
  @objc dynamic var coordinate: CLLocationCoordinate2D
  let title: String?
  let subtitle: String?
  let isLocal: Bool

  /// The one effective back-marker, already resolved by Dart. Two riders can
  /// carry the role in the journal at once (#128); exactly one arrives here
  /// flagged, so the map cannot draw two backs to one group.
  let isTec: Bool
  let needsAttention: Bool
  let riderSymbol: String
  let craftStyle: String
  let riderColor: String
  let riderColorArgb: UInt32?

  init(
    coordinate: CLLocationCoordinate2D,
    title: String,
    subtitle: String?,
    isLocal: Bool,
    isTec: Bool,
    needsAttention: Bool,
    riderSymbol: String,
    craftStyle: String,
    riderColor: String,
    riderColorArgb: UInt32?
  ) {
    self.coordinate = coordinate
    self.title = title
    self.subtitle = subtitle
    self.isLocal = isLocal
    self.isTec = isTec
    self.needsAttention = needsAttention
    self.riderSymbol = riderSymbol
    self.craftStyle = craftStyle
    self.riderColor = riderColor
    self.riderColorArgb = riderColorArgb
  }
}

/// One rider on the CarPlay map.
///
/// This is deliberately the same circular identity badge as the phone: chosen
/// colour plus chosen bike, initials or emoji. Local identity is no longer
/// replaced by a CarPlay-only blue "You" pill, and role never replaces the
/// colour a rider selected for every other surface.
private final class CarPlayRiderAnnotationView: MLNAnnotationView {
  private let label = UILabel()
  private let imageView = UIImageView()

  init(reuseIdentifier: String) {
    super.init(reuseIdentifier: reuseIdentifier)
    isEnabled = false
    frame = CGRect(x: 0, y: 0, width: 38, height: 38)
    layer.cornerRadius = 19
    layer.cornerCurve = .continuous
    layer.borderWidth = 2
    layer.borderColor = CarPlayPalette.casing.cgColor
    label.font = .systemFont(ofSize: 30, weight: .heavy)
    label.textColor = CarPlayPalette.markerGlyph
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.45
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = CarPlayPalette.markerGlyph
    addSubview(label)
    addSubview(imageView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func layoutSubviews() {
    super.layoutSubviews()
    label.frame = bounds.insetBy(dx: 2.5, dy: 2.5)
    imageView.frame = bounds.insetBy(dx: 7, dy: 7)
  }

  func apply(_ rider: CarPlayRiderAnnotation) {
    frame = CGRect(x: 0, y: 0, width: 38, height: 38)
    layer.cornerRadius = 19
    backgroundColor = rider.riderColorArgb.map(colorFromArgb)
      ?? identityColor(named: rider.riderColor)
    layer.borderColor = CarPlayPalette.casing.cgColor
    label.text = nil
    label.attributedText = nil
    label.textColor = CarPlayPalette.markerGlyph
    label.shadowColor = nil
    label.shadowOffset = .zero
    imageView.image = nil
    isAccessibilityElement = true
    accessibilityLabel = [rider.title, rider.subtitle]
      .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
      }
      .joined(separator: ". ")

    if let initials = initialsIdentity(
      symbol: rider.riderSymbol,
      fallbackName: rider.title ?? ""
    ) {
      label.attributedText = NSAttributedString(
        string: initials.text,
        attributes: [.kern: -0.8]
      )
      label.textColor = initials.color
      label.shadowColor = initials.edge
      label.shadowOffset = CGSize(width: 0.7, height: 0.7)
      label.font = .systemFont(ofSize: 30, weight: .black)
    } else if rider.riderSymbol.hasPrefix("emoji:") {
      label.text = String(rider.riderSymbol.dropFirst("emoji:".count))
      label.font = .systemFont(ofSize: 21)
    } else {
      imageView.image = craftImage(for: rider.craftStyle)
    }
    setNeedsLayout()
  }

  private func initialsIdentity(
    symbol: String,
    fallbackName: String
  ) -> (text: String, color: UIColor, edge: UIColor)? {
    if symbol == "initials" {
      return (
        riderInitials(fallbackName),
        CarPlayPalette.markerGlyph,
        UIColor.white.withAlphaComponent(0.9)
      )
    }
    guard symbol.hasPrefix("initials:v1:") else { return nil }
    let parts = symbol.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 4, parts[0] == "initials", parts[1] == "v1" else {
      return nil
    }
    let encoded = String(parts[2])
    let text: String
    if encoded.isEmpty {
      text = riderInitials(fallbackName)
    } else {
      var base64 = encoded.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
      base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
      guard
        let data = Data(base64Encoded: base64),
        let decoded = String(data: data, encoding: .utf8)
      else { return nil }
      let normalized = decoded.uppercased()
      guard
        (1...3).contains(normalized.count),
        normalized.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0)
        })
      else { return nil }
      text = normalized
    }
    let inkName = String(parts[3])
    guard let ink = initialsInk(named: inkName) else { return nil }
    let darkEdgeNames: Set<String> = ["white", "yellow", "cyan", "pink"]
    let edge = darkEdgeNames.contains(inkName)
      ? CarPlayPalette.casing.withAlphaComponent(0.9)
      : UIColor.white.withAlphaComponent(0.9)
    return (text, ink, edge)
  }

  private func riderInitials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    guard let first = words.first else { return "?" }
    if words.count == 1 { return String(first.prefix(2)).uppercased() }
    return "\(first.prefix(1))\(words.last!.prefix(1))".uppercased()
  }

  private func identityColor(named name: String) -> UIColor {
    switch name {
    case "orange": return UIColor(red: 0xFF / 255, green: 0x9F / 255, blue: 0x5A / 255, alpha: 1)
    case "yellow": return UIColor(red: 0xE8 / 255, green: 0xD2 / 255, blue: 0x4C / 255, alpha: 1)
    case "teal": return UIColor(red: 0x4F / 255, green: 0xC7 / 255, blue: 0xC7 / 255, alpha: 1)
    case "pink": return UIColor(red: 0xE8 / 255, green: 0x7F / 255, blue: 0xC0 / 255, alpha: 1)
    case "cyan": return UIColor(red: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255, alpha: 1)
    case "amber": return UIColor(red: 0xD9 / 255, green: 0xA4 / 255, blue: 0x41 / 255, alpha: 1)
    case "crimson": return UIColor(red: 0xD9 / 255, green: 0x60 / 255, blue: 0x7A / 255, alpha: 1)
    case "purple": return UIColor(red: 0x9B / 255, green: 0x7B / 255, blue: 0xFF / 255, alpha: 1)
    case "white": return UIColor(red: 0xF4 / 255, green: 0xF6 / 255, blue: 0xF8 / 255, alpha: 1)
    case "blue": return UIColor(red: 0x5B / 255, green: 0x8D / 255, blue: 0xEF / 255, alpha: 1)
    case "lime": return UIColor(red: 0xA7 / 255, green: 0xD9 / 255, blue: 0x57 / 255, alpha: 1)
    case "slate": return UIColor(red: 0x87 / 255, green: 0x96 / 255, blue: 0xA8 / 255, alpha: 1)
    default: return CarPlayPalette.rider
    }
  }

  private func initialsInk(named name: String) -> UIColor? {
    switch name {
    case "dark": return CarPlayPalette.markerGlyph
    case "white": return .white
    case "yellow": return UIColor(red: 0xFF / 255, green: 0xD8 / 255, blue: 0x4D / 255, alpha: 1)
    case "cyan": return UIColor(red: 0x3D / 255, green: 0xDC / 255, blue: 0xFF / 255, alpha: 1)
    case "pink": return UIColor(red: 0xFF / 255, green: 0x76 / 255, blue: 0xC8 / 255, alpha: 1)
    case "purple": return UIColor(red: 0x9B / 255, green: 0x7B / 255, blue: 0xFF / 255, alpha: 1)
    default: return nil
    }
  }

  private func colorFromArgb(_ argb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  private func craftImage(for style: String) -> UIImage? {
    let fileName = Self.craftFiles[style] ?? "1_four_by_four"
    let asset = "assets/icons/craft/\(fileName).png"
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      let symbol = style == "balloon" ? "balloon.fill" : "car.fill"
      return UIImage(systemName: symbol)?.withRenderingMode(.alwaysTemplate)
    }
    return UIImage(contentsOfFile: path)?.withRenderingMode(.alwaysTemplate)
  }

  private static let craftFiles = [
    "balloon": "0_balloon",
    "fourByFour": "1_four_by_four",
    "pickup": "2_pickup",
    "van": "3_van",
    "trailer": "4_trailer",
  ]
}

/// The north-up group pane beside the direction-up navigation map. It uses
/// MapLibre's snapshotter instead of a second live renderer: the tiles still
/// come from the phone's exact resolved style and shared cache, but a long ride
/// does not pay to animate two maps at every GPS fix.
private final class CarPlayGroupMiniMapView: UIView {
  private struct Rider {
    let coordinate: CLLocationCoordinate2D
    let color: UIColor
    let isLocal: Bool
    let isTec: Bool
    let isBalloon: Bool
  }

  private struct Trace {
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
    let width: CGFloat
    let casingWidth: CGFloat
    let dash: [CGFloat]
  }

  private let imageView = UIImageView()
  private let headingCaption = UILabel()
  private let caption = UILabel()
  private var snapshotter: MLNMapSnapshotter?
  private var lastRenderedAt: Date?
  private var lastStyleJSON: String?
  private var cachedStyleURL: URL?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isHidden = true
    isUserInteractionEnabled = false
    backgroundColor = CarPlayPalette.primaryPanelFill
    layer.cornerRadius = 8
    layer.cornerCurve = .continuous
    // Thicker and brighter than the 1.5 px casing it had (#442): "it blends into
    // the main map, so it is not obvious which is which". A hairline in the
    // casing colour is invisible against a basemap that is mostly the same
    // greys.
    layer.borderWidth = 3
    layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.6
    layer.shadowRadius = 6
    layer.shadowOffset = .zero
    layer.masksToBounds = false
    clipsToBounds = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    addSubview(imageView)

    headingCaption.translatesAutoresizingMaskIntoConstraints = false
    headingCaption.text = "NORTH UP · GROUP MAP"
    headingCaption.font = .systemFont(ofSize: 11, weight: .black)
    headingCaption.textColor = CarPlayPalette.cardTitle
    headingCaption.backgroundColor = CarPlayPalette.cardFill
    headingCaption.layer.cornerRadius = 6
    headingCaption.layer.cornerCurve = .continuous
    headingCaption.clipsToBounds = true
    headingCaption.textAlignment = .center
    addSubview(headingCaption)

    caption.translatesAutoresizingMaskIntoConstraints = false
    caption.font = .systemFont(ofSize: 12, weight: .bold)
    caption.textColor = CarPlayPalette.cardTitle
    caption.backgroundColor = CarPlayPalette.cardFill
    caption.layer.cornerRadius = 6
    caption.layer.cornerCurve = .continuous
    caption.clipsToBounds = true
    caption.textAlignment = .center
    caption.adjustsFontSizeToFitWidth = true
    caption.minimumScaleFactor = 0.7
    caption.numberOfLines = 2
    addSubview(caption)

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      headingCaption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      headingCaption.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      headingCaption.heightAnchor.constraint(equalToConstant: 22),
      headingCaption.widthAnchor.constraint(equalToConstant: 142),
      caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      caption.heightAnchor.constraint(equalToConstant: 40),
    ])
  }

  /// The east-west span of the overview, in the rider's own units.
  ///
  /// The width rather than the diagonal: it is what the eye reads across the
  /// picture, and it is the number a map scale bar has always meant.
  static func spanLabel(
    for bounds: MLNCoordinateBounds,
    usesMiles: Bool
  ) -> String {
    let west = CLLocation(
      latitude: bounds.sw.latitude,
      longitude: bounds.sw.longitude
    )
    let east = CLLocation(
      latitude: bounds.sw.latitude,
      longitude: bounds.ne.longitude
    )
    let meters = west.distance(from: east)
    if usesMiles {
      let miles = meters / 1_609.344
      return miles < 0.5
        ? "\(Int((meters / 0.9144).rounded())) yd"
        : String(format: "%.1f mi", miles)
    }
    return meters < 950
      ? "\(Int(meters.rounded())) m"
      : String(format: "%.1f km", meters / 1_000)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func apply(
    snapshot: [String: Any],
    styleURL: URL?,
    styleJSON: String?,
    force: Bool = false
  ) {
    let riders = projectedRiders(from: snapshot)
    let traces = projectedTraces(from: snapshot)
    guard !riders.isEmpty else {
      isHidden = true
      snapshotter?.cancel()
      snapshotter = nil
      return
    }

    isHidden = false
    let usesMiles = (snapshot["distanceUnit"] as? String) == "miles"
    let framingCoordinates = riders.map(\.coordinate)
      + traces.flatMap(\.coordinates)
    let bounds = Self.groupBounds(for: framingCoordinates)
    let span = Self.spanLabel(
      for: bounds,
      usesMiles: usesMiles
    )
    let local = riders.first(where: \.isLocal)
    let balloon = riders.first(where: \.isBalloon)
    let directDistance = local.flatMap { local in
      balloon.map {
        CLLocation(latitude: local.coordinate.latitude, longitude: local.coordinate.longitude)
          .distance(from: CLLocation(
            latitude: $0.coordinate.latitude,
            longitude: $0.coordinate.longitude
          ))
      }
    }
    let distance = directDistance.map {
      Self.distanceLabel($0, usesMiles: usesMiles)
    } ?? "position unavailable"
    let routeTargetsBalloon =
      (snapshot["routeTargetsBalloon"] as? NSNumber)?.boolValue ?? false
    let remainingSeconds = routeTargetsBalloon
      ? ((snapshot["journeyProgress"] as? [String: Any])?["remainingSeconds"]
        as? NSNumber)?.doubleValue
      : nil
    let roadTime = remainingSeconds.map(Self.durationLabel) ?? "road time —"
    caption.text = "  BALLOON \(distance) · \(roadTime)\n  \(riders.count) craft · span \(span)  "
    accessibilityLabel =
      "North-up group map. Balloon \(distance). \(roadTime). "
      + "\(riders.count) craft visible."

    let now = Date()
    if !force,
      snapshotter != nil
        || lastRenderedAt.map({ now.timeIntervalSince($0) < 2 }) == true
    {
      return
    }
    if force {
      snapshotter?.cancel()
      snapshotter = nil
      lastRenderedAt = nil
    }
    guard let resolvedStyleURL = resolvedStyleURL(json: styleJSON, fallback: styleURL)
    else { return }

    let camera = MLNMapCamera(
      lookingAtCenter: CLLocationCoordinate2D(
        latitude: (bounds.sw.latitude + bounds.ne.latitude) / 2,
        longitude: (bounds.sw.longitude + bounds.ne.longitude) / 2
      ),
      altitude: 2_000,
      pitch: 0,
      heading: 0
    )
    // Render at the whole left-pane size so labels, traces and the balloon stay
    // crisp on both compact and wide head units.
    let renderSize = self.bounds.width >= 100 && self.bounds.height >= 60
      ? self.bounds.size
      : CGSize(width: 160, height: 95)
    let options = MLNMapSnapshotOptions(
      styleURL: resolvedStyleURL,
      camera: camera,
      size: renderSize
    )
    options.coordinateBounds = bounds
    options.showsLogo = false
    options.showsAttribution = false
    options.scale = min(2, UIScreen.main.scale)

    let snapshotter = MLNMapSnapshotter(options: options)
    self.snapshotter = snapshotter
    snapshotter.start(
      overlayHandler: { overlay in
        Self.draw(
          traces: traces,
          directLine: local.flatMap { local in
            balloon.map { [local.coordinate, $0.coordinate] }
          },
          riders: riders,
          on: overlay
        )
      },
      completionHandler: { [weak self, weak snapshotter] snapshot, _ in
        guard let self, self.snapshotter === snapshotter else { return }
        self.snapshotter = nil
        self.lastRenderedAt = Date()
        if let image = snapshot?.image {
          self.imageView.image = image
        }
      }
    )
  }

  private func resolvedStyleURL(json: String?, fallback: URL?) -> URL? {
    guard let json, !json.isEmpty else { return fallback }
    if json == lastStyleJSON, let cachedStyleURL { return cachedStyleURL }
    guard
      let directory = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
      ).first
    else { return fallback }
    let file = directory.appendingPathComponent("carplay-group-map-style.json")
    do {
      try Data(json.utf8).write(to: file, options: .atomic)
      lastStyleJSON = json
      cachedStyleURL = file
      return file
    } catch {
      return fallback
    }
  }

  private func projectedRiders(from snapshot: [String: Any]) -> [Rider] {
    var rawRiders = snapshot["riders"] as? [[String: Any]] ?? []
    if let local = snapshot["localRider"] as? [String: Any] {
      let localID = local["riderId"] as? String
      if
        let index = rawRiders.firstIndex(where: {
          ($0["riderId"] as? String) == localID
        })
      {
        rawRiders[index].merge(local) { _, localValue in localValue }
      } else {
        rawRiders.append(local)
      }
    }
    return rawRiders.compactMap { raw in
      guard let coordinate = Self.coordinate(from: raw) else { return nil }
      return Rider(
        coordinate: coordinate,
        color: (raw["riderColorArgb"] as? NSNumber)
          .map { Self.colorFromArgb($0.uint32Value) }
          ?? Self.identityColor(named: raw["riderColor"] as? String),
        isLocal: (raw["isLocal"] as? NSNumber)?.boolValue ?? false,
        isTec: (raw["isTec"] as? NSNumber)?.boolValue ?? false,
        isBalloon:
          ((raw["craftStyle"] as? String)
            ?? (raw["motorcycleStyle"] as? String)) == "balloon"
      )
    }
  }

  private func projectedTraces(from snapshot: [String: Any]) -> [Trace] {
    (snapshot["sharedTraces"] as? [[String: Any]] ?? []).compactMap { raw in
      let coordinates = (raw["points"] as? [[String: Any]] ?? [])
        .compactMap(Self.coordinate(from:))
      guard
        coordinates.count >= 2,
        let color = (raw["colorArgb"] as? NSNumber)?.uint32Value,
        let width = (raw["width"] as? NSNumber)?.doubleValue,
        let casingWidth = (raw["casingWidth"] as? NSNumber)?.doubleValue
      else { return nil }
      return Trace(
        coordinates: coordinates,
        color: Self.colorFromArgb(color),
        width: CGFloat(width),
        casingWidth: CGFloat(casingWidth),
        dash: (raw["dash"] as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
      )
    }
  }

  private static func groupBounds(
    for coordinates: [CLLocationCoordinate2D]
  ) -> MLNCoordinateBounds {
    let latitudes = coordinates.map(\.latitude)
    let longitudes = coordinates.map(\.longitude)
    let minimumLatitude = latitudes.min() ?? 0
    let maximumLatitude = latitudes.max() ?? 0
    let minimumLongitude = longitudes.min() ?? 0
    let maximumLongitude = longitudes.max() ?? 0
    let latitudeSpan = max(0.004, maximumLatitude - minimumLatitude)
    let middleLatitude = (minimumLatitude + maximumLatitude) / 2
    let longitudeScale = max(0.25, abs(cos(middleLatitude * .pi / 180)))
    let longitudeSpan = max(0.004 / longitudeScale, maximumLongitude - minimumLongitude)
    let latitudePadding = latitudeSpan * 0.38
    let longitudePadding = longitudeSpan * 0.38
    return MLNCoordinateBoundsMake(
      CLLocationCoordinate2D(
        latitude: max(-90, minimumLatitude - latitudePadding),
        longitude: max(-180, minimumLongitude - longitudePadding)
      ),
      CLLocationCoordinate2D(
        latitude: min(90, maximumLatitude + latitudePadding),
        longitude: min(180, maximumLongitude + longitudePadding)
      )
    )
  }

  private static func draw(
    traces: [Trace],
    directLine: [CLLocationCoordinate2D]?,
    riders: [Rider],
    on overlay: MLNMapSnapshotOverlay
  ) {
    let context = overlay.context
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: overlay.context.boundingBoxOfClipPath)

    for trace in traces {
      let points = trace.coordinates.map(overlay.point(for:))
      context.setLineCap(.round)
      context.setLineJoin(.round)
      addPath(points, to: context)
      context.setStrokeColor(CarPlayPalette.casing.cgColor)
      context.setLineWidth(trace.casingWidth)
      context.setLineDash(phase: 0, lengths: trace.dash)
      context.strokePath()
      addPath(points, to: context)
      context.setStrokeColor(trace.color.cgColor)
      context.setLineWidth(trace.width)
      context.setLineDash(phase: 0, lengths: trace.dash)
      context.strokePath()
    }

    if let directLine, directLine.count == 2 {
      addPath(directLine.map(overlay.point(for:)), to: context)
      context.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
      context.setLineWidth(2.5)
      context.setLineDash(phase: 0, lengths: [7, 5])
      context.strokePath()
    }

    context.setLineDash(phase: 0, lengths: [])
    for rider in riders {
      let point = overlay.point(for: rider.coordinate)
      let radius: CGFloat = rider.isBalloon ? 13 : (rider.isLocal ? 9 : 7)
      let rect = CGRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      if rider.isTec {
        context.setStrokeColor(CarPlayPalette.balloonBlue.cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: rect.insetBy(dx: -3, dy: -3))
      }
      context.setFillColor(rider.color.cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(
        (rider.isLocal ? UIColor.white : CarPlayPalette.casing).cgColor
      )
      context.setLineWidth(rider.isLocal ? 2.5 : 2)
      context.strokeEllipse(in: rect)
      if rider.isBalloon {
        drawBalloonGlyph(at: point, in: context)
      }
    }
  }

  private static func drawBalloonGlyph(at point: CGPoint, in context: CGContext) {
    context.setFillColor(CarPlayPalette.markerGlyph.cgColor)
    context.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 8, width: 10, height: 12))
    context.setStrokeColor(CarPlayPalette.markerGlyph.cgColor)
    context.setLineWidth(1.5)
    context.beginPath()
    context.move(to: CGPoint(x: point.x - 3.5, y: point.y + 2))
    context.addLine(to: CGPoint(x: point.x - 2, y: point.y + 6))
    context.move(to: CGPoint(x: point.x + 3.5, y: point.y + 2))
    context.addLine(to: CGPoint(x: point.x + 2, y: point.y + 6))
    context.strokePath()
    context.fill(CGRect(x: point.x - 3, y: point.y + 5.5, width: 6, height: 3.5))
  }

  private static func distanceLabel(_ metres: Double, usesMiles: Bool) -> String {
    if usesMiles {
      let miles = metres / 1_609.344
      return miles < 0.1
        ? "\(Int((metres * 1.093613).rounded())) yd"
        : String(format: "%.1f mi", miles)
    }
    return metres < 1_000
      ? "\(Int(metres.rounded())) m"
      : String(format: "%.1f km", metres / 1_000)
  }

  private static func durationLabel(_ seconds: Double) -> String {
    let minutes = max(1, Int(ceil(seconds / 60)))
    if minutes < 60 { return "road ~\(minutes) min" }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0
      ? "road ~\(hours) h"
      : "road ~\(hours) h \(remainder) min"
  }

  private static func addPath(_ points: [CGPoint], to context: CGContext) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() { context.addLine(to: point) }
  }

  private static func coordinate(from raw: [String: Any]) -> CLLocationCoordinate2D? {
    guard
      let latitude = (raw["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (raw["longitude"] as? NSNumber)?.doubleValue,
      (-90 ... 90).contains(latitude),
      (-180 ... 180).contains(longitude)
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  private static func identityColor(named name: String?) -> UIColor {
    switch name {
    case "orange": return UIColor(red: 1, green: 0x9F / 255, blue: 0x5A / 255, alpha: 1)
    case "yellow": return UIColor(red: 0xE8 / 255, green: 0xD2 / 255, blue: 0x4C / 255, alpha: 1)
    case "teal": return UIColor(red: 0x4F / 255, green: 0xC7 / 255, blue: 0xC7 / 255, alpha: 1)
    case "pink": return UIColor(red: 0xE8 / 255, green: 0x7F / 255, blue: 0xC0 / 255, alpha: 1)
    case "cyan": return UIColor(red: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255, alpha: 1)
    case "amber": return UIColor(red: 0xD9 / 255, green: 0xA4 / 255, blue: 0x41 / 255, alpha: 1)
    case "crimson": return UIColor(red: 0xD9 / 255, green: 0x60 / 255, blue: 0x7A / 255, alpha: 1)
    default: return CarPlayPalette.rider
    }
  }

  private static func colorFromArgb(_ argb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}

/// App-owned compass paired with the speed sign. Its footprint is deliberately
/// the same 34-point circle as [CarPlaySpeedLimitBadge]'s sign.
private final class CarPlayCompassBadge: UIView {
  private let arrow = UIImageView()
  private let north = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.cornerRadius = 17
    layer.cornerCurve = .continuous
    layer.borderWidth = 2
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.4
    layer.shadowRadius = 4
    layer.shadowOffset = CGSize(width: 0, height: 2)

    arrow.translatesAutoresizingMaskIntoConstraints = false
    arrow.image = UIImage(systemName: "location.north.fill")
    arrow.contentMode = .scaleAspectFit
    arrow.tintColor = CarPlayPalette.emergencyFill
    addSubview(arrow)
    north.translatesAutoresizingMaskIntoConstraints = false
    north.text = "N"
    north.font = .systemFont(ofSize: 8, weight: .black)
    north.textAlignment = .center
    addSubview(north)
    NSLayoutConstraint.activate([
      arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
      arrow.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 2),
      arrow.widthAnchor.constraint(equalToConstant: 16),
      arrow.heightAnchor.constraint(equalToConstant: 16),
      north.centerXAnchor.constraint(equalTo: centerXAnchor),
      north.topAnchor.constraint(equalTo: topAnchor, constant: 3),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func apply(direction: CLLocationDirection, darkMap: Bool) {
    backgroundColor = darkMap
      ? CarPlayPalette.cardFill
      : UIColor.white.withAlphaComponent(0.90)
    layer.borderColor = (
      darkMap ? UIColor(red: 0x89 / 255, green: 0x93 / 255, blue: 0xA0 / 255, alpha: 1)
        : UIColor(red: 0x30 / 255, green: 0x34 / 255, blue: 0x3B / 255, alpha: 1)
    ).cgColor
    north.textColor = darkMap ? .white : .black
    arrow.transform = CGAffineTransform(rotationAngle: -direction * .pi / 180)
    accessibilityLabel = "Map heading \(Int(direction.rounded())) degrees"
  }
}

/// Phone-style turn card used instead of starting a template navigation
/// session. The latter always adds Apple's separate trip-estimate panel, which
/// cannot be hidden independently.
private final class CarPlayGuidanceView: UIView {
  private let symbol = UIImageView()
  private let title = UILabel()
  private let detail = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isHidden = true
    isUserInteractionEnabled = false
    backgroundColor = CarPlayPalette.primaryPanelFill
    layer.cornerRadius = 10
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor

    symbol.translatesAutoresizingMaskIntoConstraints = false
    symbol.contentMode = .scaleAspectFit
    symbol.tintColor = CarPlayPalette.routeAhead
    addSubview(symbol)
    title.translatesAutoresizingMaskIntoConstraints = false
    title.font = .systemFont(ofSize: 17, weight: .bold)
    title.textColor = CarPlayPalette.cardTitle
    title.numberOfLines = 2
    title.adjustsFontSizeToFitWidth = true
    title.minimumScaleFactor = 0.76
    addSubview(title)
    detail.translatesAutoresizingMaskIntoConstraints = false
    detail.font = .systemFont(ofSize: 12, weight: .semibold)
    detail.textColor = CarPlayPalette.cardLabel
    detail.numberOfLines = 1
    detail.adjustsFontSizeToFitWidth = true
    detail.minimumScaleFactor = 0.76
    addSubview(detail)
    NSLayoutConstraint.activate([
      symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
      symbol.widthAnchor.constraint(equalToConstant: 30),
      symbol.heightAnchor.constraint(equalToConstant: 30),
      title.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 9),
      title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
      detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
      detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func apply(snapshot: [String: Any]) {
    let marker = snapshot["marker"] as? [String: Any]
    let headline = Self.nonEmpty(marker?["title"])
      ?? Self.nonEmpty(snapshot["guidanceTitle"])
    guard
      let headline,
      marker != nil || !headline.lowercased().contains("no more turns")
    else {
      isHidden = true
      return
    }
    isHidden = false
    title.text = headline
    detail.text = Self.nonEmpty(marker?["detail"])
      ?? Self.nonEmpty(snapshot["guidanceDetail"])
    symbol.image = UIImage(systemName: Self.symbolName(for: headline))
    accessibilityLabel = [headline, detail.text].compactMap { $0 }.joined(separator: ". ")
  }

  private static func nonEmpty(_ raw: Any?) -> String? {
    guard let value = raw as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func symbolName(for title: String) -> String {
    let lower = title.lowercased()
    if lower.contains("roundabout") { return "arrow.clockwise.circle" }
    if lower.contains("left") { return "arrow.turn.up.left" }
    if lower.contains("right") { return "arrow.turn.up.right" }
    if lower.contains("arrive") || lower.contains("destination") {
      return "flag.checkered"
    }
    return "arrow.up"
  }
}

/// The active-ride controls use the same labelled action language as phone
/// landscape. Generic template follow/browse buttons are intentionally absent;
/// Follow appears only after a deliberate pan.
private final class CarPlayRideActionsView: UIStackView {
  private let follow = CarPlayRideActionButton(
    title: "FOLLOW",
    symbol: "location.north",
    fill: CarPlayPalette.cardFill,
    ink: CarPlayPalette.actionInk
  )
  private let alert = CarPlayRideActionButton(
    title: "ALERT",
    symbol: "sos",
    fill: CarPlayPalette.emergencyFill,
    ink: .white
  )
  private let leave = CarPlayRideActionButton(
    title: "LEAVE",
    symbol: "rectangle.portrait.and.arrow.right",
    fill: CarPlayPalette.leaveFill,
    ink: .white
  )
  private let report = CarPlayRideActionButton(
    title: "REPORT",
    symbol: "bell.badge.fill",
    fill: CarPlayPalette.cardFill,
    ink: CarPlayPalette.reportAccent
  )

  var onFollow: (() -> Void)?
  var onReport: (() -> Void)?
  var onEmergency: (() -> Void)?
  var onLeave: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    axis = .vertical
    alignment = .fill
    distribution = .fill
    spacing = 10
    for button in [follow, alert, leave, report] {
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
      button.widthAnchor.constraint(equalToConstant: 82).isActive = true
      addArrangedSubview(button)
    }
    follow.addAction(UIAction { [weak self] _ in self?.onFollow?() }, for: .primaryActionTriggered)
    alert.addAction(UIAction { [weak self] _ in self?.onEmergency?() }, for: .primaryActionTriggered)
    leave.addAction(UIAction { [weak self] _ in self?.onLeave?() }, for: .primaryActionTriggered)
    report.addAction(UIAction { [weak self] _ in self?.onReport?() }, for: .primaryActionTriggered)
    setFollowing(true)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func setFollowing(_ following: Bool) {
    follow.isHidden = following
  }
}

private final class CarPlayRideActionButton: UIButton {
  init(title: String, symbol: String, fill: UIColor, ink: UIColor) {
    super.init(frame: .zero)
    var configuration = UIButton.Configuration.filled()
    configuration.title = title
    configuration.image = UIImage(systemName: symbol)
    configuration.imagePadding = 4
    configuration.imagePlacement = .leading
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 10,
      weight: .bold
    )
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 6,
      leading: 6,
      bottom: 6,
      trailing: 6
    )
    configuration.titleLineBreakMode = .byClipping
    configuration.baseBackgroundColor = fill
    configuration.baseForegroundColor = ink
    configuration.cornerStyle = .large
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: 7, weight: .black)
      return outgoing
    }
    self.configuration = configuration
    titleLabel?.numberOfLines = 1
    titleLabel?.adjustsFontSizeToFitWidth = true
    titleLabel?.minimumScaleFactor = 0.72
    accessibilityLabel = title.capitalized
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  /// The visual button is deliberately compact, but the effective target keeps
  /// CarPlay's 44-point minimum. Ten-point stack spacing means neighbouring
  /// expanded targets meet without overlapping.
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.insetBy(dx: -5, dy: -5).contains(point)
  }
}

/// The phone's landscape speed-limit sign and current-speed readout, scaled for
/// CarPlay's shorter map canvas. The upper number is always the mapped UK mph
/// limit and the number below is always GPS speed in mph, just as on the phone.
private final class CarPlaySpeedLimitBadge: UIView {
  private let sign = UIView()
  private let limitLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let speedLabel = UILabel()

  init() {
    super.init(frame: .zero)
    isHidden = true
    isUserInteractionEnabled = false

    sign.translatesAutoresizingMaskIntoConstraints = false
    sign.backgroundColor = .white
    sign.layer.cornerRadius = 17
    sign.layer.borderWidth = 4
    sign.layer.shadowColor = UIColor.black.cgColor
    sign.layer.shadowOpacity = 0.4
    sign.layer.shadowRadius = 4
    sign.layer.shadowOffset = CGSize(width: 0, height: 2)
    addSubview(sign)

    limitLabel.translatesAutoresizingMaskIntoConstraints = false
    limitLabel.font = .systemFont(ofSize: 18, weight: .black)
    limitLabel.textColor = UIColor(
      red: 0x11 / 255,
      green: 0x11 / 255,
      blue: 0x11 / 255,
      alpha: 1
    )
    limitLabel.textAlignment = .center
    limitLabel.adjustsFontSizeToFitWidth = true
    limitLabel.minimumScaleFactor = 0.7
    sign.addSubview(limitLabel)

    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.color = UIColor(
      red: 0x30 / 255,
      green: 0x34 / 255,
      blue: 0x3B / 255,
      alpha: 1
    )
    sign.addSubview(spinner)

    speedLabel.translatesAutoresizingMaskIntoConstraints = false
    speedLabel.textAlignment = .center
    speedLabel.adjustsFontSizeToFitWidth = true
    speedLabel.minimumScaleFactor = 0.7
    addSubview(speedLabel)

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 44),
      heightAnchor.constraint(equalToConstant: 58),
      sign.widthAnchor.constraint(equalToConstant: 34),
      sign.heightAnchor.constraint(equalToConstant: 34),
      sign.topAnchor.constraint(equalTo: topAnchor),
      sign.centerXAnchor.constraint(equalTo: centerXAnchor),
      limitLabel.leadingAnchor.constraint(equalTo: sign.leadingAnchor, constant: 4),
      limitLabel.trailingAnchor.constraint(equalTo: sign.trailingAnchor, constant: -4),
      limitLabel.centerYAnchor.constraint(equalTo: sign.centerYAnchor),
      spinner.centerXAnchor.constraint(equalTo: sign.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: sign.centerYAnchor),
      speedLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
      speedLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      speedLabel.topAnchor.constraint(equalTo: sign.bottomAnchor, constant: 2),
      speedLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func apply(_ speed: [String: Any]?) {
    guard let speed else {
      isHidden = true
      spinner.stopAnimating()
      return
    }
    isHidden = false

    let status = speed["limitStatus"] as? String
    let limit = (speed["limitMilesPerHour"] as? NSNumber)?.intValue
    let unlimited = (speed["limitUnlimited"] as? NSNumber)?.boolValue ?? false
    let known = status == "known" && (limit != nil || unlimited)
    let checking = status == "checking"
    limitLabel.isHidden = checking
    if checking {
      spinner.startAnimating()
    } else {
      spinner.stopAnimating()
      limitLabel.text = known ? (unlimited ? "∞" : "\(limit!)") : "–"
    }
    sign.layer.borderColor = (
      known
        ? UIColor(red: 0xD7 / 255, green: 0x19 / 255, blue: 0x20 / 255, alpha: 1)
        : UIColor(red: 0x89 / 255, green: 0x93 / 255, blue: 0xA0 / 255, alpha: 1)
    ).cgColor

    let metresPerSecond = (speed["metresPerSecond"] as? NSNumber)?.doubleValue
    let milesPerHour = metresPerSecond.flatMap { value in
      value.isFinite && value >= 0 ? Int((value * 2.236_936).rounded()) : nil
    }
    let currentSpeed = milesPerHour.map(String.init) ?? "–"
    speedLabel.attributedText = NSAttributedString(
      string: currentSpeed,
      attributes: [
        .font: UIFont.systemFont(ofSize: 18, weight: .black),
        .foregroundColor: UIColor.white,
        .strokeColor: UIColor.black.withAlphaComponent(0.9),
        .strokeWidth: -3,
      ]
    )
    let ageing = (speed["isAgeing"] as? NSNumber)?.boolValue ?? false
    speedLabel.alpha = ageing ? 0.55 : 1

    let limitDescription = known
      ? (unlimited ? "unrestricted" : "\(limit!) miles per hour")
      : "unavailable"
    let speedDescription = milesPerHour.map { "\($0) miles per hour" }
      ?? "unavailable"
    accessibilityLabel = "Mapped speed limit \(limitDescription). "
      + "Your GPS speed is \(speedDescription)."
  }
}

/// The time of day on the CarPlay map, drawn by the app (#452).
///
/// > Show the time on the map in landscape mode and on CarPlay but don't use
/// > Apple's built in widgets to do it.
///
/// A `DateFormatter` with the `j:mm` template rather than a hard "HH:mm": `j`
/// resolves to whichever of 12- or 24-hour the head unit's locale uses, so a car
/// set to a 12-hour clock does not suddenly show 13:00.
///
/// It ticks on the minute, not the second. A clock showing hours and minutes only
/// changes sixty times an hour, and this view is over a moving map.
final class CarPlayClockLabel: UIView {
  private let label = UILabel()
  private var tick: Timer?
  private let formatter = DateFormatter()

  /// Overridden by tests; production reads the device clock.
  var clock: () -> Date = Date.init

  override init(frame: CGRect) {
    super.init(frame: frame)
    formatter.setLocalizedDateFormatFromTemplate("j:mm")
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    label.textColor = .white
    // The map behind this is any colour, so the glyphs carry their own shadow
    // rather than a panel — the same reasoning as the phone's map labels.
    label.layer.shadowColor = UIColor.black.cgColor
    label.layer.shadowOpacity = 0.8
    label.layer.shadowRadius = 4
    label.layer.shadowOffset = .zero
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor),
      label.trailingAnchor.constraint(equalTo: trailingAnchor),
      label.topAnchor.constraint(equalTo: topAnchor),
      label.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    isUserInteractionEnabled = false
    refresh()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  deinit { tick?.invalidate() }

  func apply(darkMap: Bool) {
    label.textColor = darkMap ? .white : .black
    label.layer.shadowColor = (darkMap ? UIColor.black : UIColor.white).cgColor
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // Stopped when the view leaves the window, so a disconnected head unit does
    // not keep a timer alive.
    window == nil ? tick?.invalidate() : refresh()
  }

  private func refresh() {
    let now = clock()
    label.text = formatter.string(from: now)
    tick?.invalidate()
    guard window != nil else { return }
    // Rescheduled from the new time rather than repeating a fixed minute: a timer
    // that drifts eventually fires just before the boundary and shows the minute
    // that has already passed.
    let seconds = Calendar.current.component(.second, from: now)
    let delay = max(1, 60 - seconds)
    tick = Timer.scheduledTimer(
      withTimeInterval: TimeInterval(delay),
      repeats: false
    ) { [weak self] _ in
      self?.refresh()
    }
  }
}
