import Foundation
import CoreLocation
import Combine

struct WeatherSnapshot: Equatable {
    var temperatureC: Double
    var symbolName: String
    var summary: String
    /// The next few hours. Empty if the forecast did not come back — the
    /// current conditions are still worth showing on their own.
    var hourly: [Hour] = []

    struct Hour: Equatable, Identifiable {
        let date: Date
        let temperatureC: Double
        let symbolName: String
        var id: Date { date }

        /// "2 PM" / "14" — hour only, because the strip is 60pt wide per column
        /// and the minutes are always zero.
        var hourText: String {
            date.formatted(.dateTime.hour())
        }

        var temperatureText: String {
            WeatherSnapshot.format(temperatureC)
        }
    }

    /// Localized temperature in the user's preferred unit ("72°" / "22°").
    var temperatureText: String { Self.format(temperatureC) }

    static func format(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(
                width: .narrow,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0))
            ))
    }
}

/// Publishes current conditions for the user's location. Uses CoreLocation for
/// a coarse position and the keyless Open-Meteo API for conditions, so it works
/// without a WeatherKit entitlement. When location access is denied the UI
/// simply hides the weather pill.
final class WeatherProvider: NSObject, ObservableObject {
    @Published private(set) var current: WeatherSnapshot?

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var isRunning = false
    private let refreshInterval: TimeInterval = 20 * 60

    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        requestLocationIfAuthorized()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.requestLocationIfAuthorized()
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        current = nil
    }

    /// Fetch as soon as location access is granted from elsewhere, rather than
    /// waiting up to 20 minutes for the next scheduled refresh.
    func reevaluateAccess() {
        guard isRunning else { return }
        requestLocationIfAuthorized()
    }

    private func requestLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break // denied/restricted: weather stays hidden
        }
    }

    // MARK: - Fetch

    private func fetch(latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            // The forecast rides along on the request already being made — the
            // same endpoint, no extra key, no second round trip.
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "forecast_days", value: "2"),
            // Epoch seconds rather than local wall-clock strings, so there is
            // no date parsing to get wrong across time zones.
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            else { return }

            let c = response.current
            let (symbol, summary) = Self.condition(for: c.weather_code, isDay: c.is_day == 1)
            let snapshot = WeatherSnapshot(
                temperatureC: c.temperature_2m,
                symbolName: symbol,
                summary: summary,
                hourly: Self.hours(from: response.hourly)
            )
            DispatchQueue.main.async { self?.current = snapshot }
        }.resume()
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [Int]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        let current: Current
        let hourly: Hourly?
    }

    /// The next six hours, starting with the one after this one.
    ///
    /// Six because that is what fits across the panel header without shrinking
    /// the columns below reading size, and because the question a temperature
    /// readout actually provokes — do I need a jacket, will it rain later — is
    /// answered inside an afternoon rather than a week.
    private static func hours(from hourly: OpenMeteoResponse.Hourly?) -> [WeatherSnapshot.Hour] {
        guard let hourly else { return [] }
        // Every array is parallel; a short one means a truncated response, and
        // zipping past its end would crash rather than degrade.
        let count = min(hourly.time.count, hourly.temperature_2m.count,
                        hourly.weather_code.count, hourly.is_day.count)
        guard count > 0 else { return [] }

        let now = Date()
        return (0..<count).lazy
            .map { i -> WeatherSnapshot.Hour in
                let (symbol, _) = condition(for: hourly.weather_code[i],
                                            isDay: hourly.is_day[i] == 1)
                return WeatherSnapshot.Hour(
                    date: Date(timeIntervalSince1970: TimeInterval(hourly.time[i])),
                    temperatureC: hourly.temperature_2m[i],
                    symbolName: symbol
                )
            }
            .filter { $0.date > now }
            .prefix(6)
            .map { $0 }
    }

    /// Maps WMO weather codes to an SF Symbol + short description.
    private static func condition(for code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0:          return (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1, 2:       return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3:          return ("cloud.fill", "Overcast")
        case 45, 48:     return ("cloud.fog.fill", "Fog")
        case 51...57:    return ("cloud.drizzle.fill", "Drizzle")
        case 61...67:    return ("cloud.rain.fill", "Rain")
        case 71...77:    return ("cloud.snow.fill", "Snow")
        case 80...82:    return ("cloud.heavyrain.fill", "Showers")
        case 85, 86:     return ("cloud.snow.fill", "Snow showers")
        case 95...99:    return ("cloud.bolt.rain.fill", "Thunderstorm")
        default:         return ("cloud.fill", "—")
        }
    }
}

extension WeatherProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, let location = locations.last else { return }
        fetch(latitude: location.coordinate.latitude,
              longitude: location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last snapshot; try again on the next timer tick.
    }
}
