import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var weatherViewModel = WeatherViewModel()
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            VStack(spacing: 20) {
                // Location and Date
                VStack {
                    Text(weatherViewModel.locationName ?? "Locating...")
                        .font(.largeTitle)
                        .bold()
                    Text(formattedDate())
                        .font(.headline)
                }
                .padding(.top)

                // Current Weather
                Text(weatherViewModel.currentWeather?.description ?? "Loading...")
                    .font(.title2)

                // Temperature Comparison
                HStack(spacing: 30) {
                    TemperatureView(title: "Today", temperature: weatherViewModel.currentTemperature ?? 0)
                    TemperatureView(title: "Last Year", temperature: weatherViewModel.lastYearTemperature ?? 0)
                }
                .padding()

                // Daily Summary
                Text("Daily Summary")
                    .font(.headline)
                    .padding(.top)
                Text(dailySummary())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Additional Weather Info
                HStack(spacing: 30) {
                    WeatherInfoView(iconName: "wind", value: "\(Int(weatherViewModel.currentWeather?.windspeed ?? 0))km/h", title: "Wind")
                    WeatherInfoView(iconName: "drop.fill", value: "48%", title: "Humidity")
                    WeatherInfoView(iconName: "eye.fill", value: "1.6km", title: "Visibility")
                }
                .padding()

            }
            .background(Color.white.opacity(0.2))
            .tabItem {
                Image(systemName: "sun.max.fill")
                Text("Today")
            }
            .tag(0)

            // Weekly Comparison Tab
            List {
                if weatherViewModel.weeklyComparison.isEmpty {
                    ProgressView("Fetching Data...")
                } else {
                    ForEach(weatherViewModel.weeklyComparison, id: \.date) { data in
                        HStack {
                            Text(data.dateFormatted)
                            Spacer()
                            Text("Now: \(String(format: "%.1f", data.currentTemp))°C")
                            Text("Last Year: \(String(format: "%.1f", data.lastYearTemp))°C")
                        }
                    }
                }
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("Last 7 Days")
            }
            .tag(1)
        }
        .accentColor(.black)
        .onAppear {
            weatherViewModel.requestLocation()
        }
    }

    private func formattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, d MMMM"
        return dateFormatter.string(from: Date())
    }

    private func dailySummary() -> String {
        guard let current = weatherViewModel.currentTemperature,
              let lastYear = weatherViewModel.lastYearTemperature else {
            return "Loading weather information..."
        }
        
        let difference = current - lastYear
        let comparisonText: String
        
        if difference > 0 {
            comparisonText = "colder than"
        } else if difference < 0 {
            comparisonText = "hotter than"
        } else {
            comparisonText = "the same as"
        }
        
        return "Last year it was +\(Int(lastYear))°, which is \(comparisonText) today by \(abs(Int(difference)))°."
    }
}

struct TemperatureView: View {
    let title: String
    let temperature: Double

    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            Text("\(Int(temperature))°")
                .font(.system(size: 60, weight: .bold))
        }
    }
}

struct WeatherInfoView: View {
    let iconName: String
    let value: String
    let title: String

    var body: some View {
        VStack {
            Image(systemName: iconName)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
        }
    }
}

struct DayForecastView: View {
    let date: Date
    let temperature: Double

    var body: some View {
        VStack {
            Text("\(Int(temperature))°")
                .font(.title3)
            Image(systemName: "sun.max.fill")
                .foregroundColor(.yellow)
            Text(formattedDate())
                .font(.caption)
        }
        .padding()
        .background(Color.white.opacity(0.2))
        .cornerRadius(10)
    }

    private func formattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        return dateFormatter.string(from: date)
    }
}

class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationName: String?
    @Published var currentTemperature: Double?
    @Published var lastYearTemperature: Double?
    @Published var currentWeather: CurrentWeather?
    @Published var weeklyComparison: [WeatherComparison] = []

    private let locationManager = CLLocationManager()
    private var latitude: Double?
    private var longitude: Double?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // CLLocationManagerDelegate Methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude

            fetchLocationName(location: location)
            fetchWeatherData()
            fetchWeeklyComparison()

            locationManager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
    }

    // Fetch location name using reverse geocoding
    private func fetchLocationName(location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let placemark = placemarks?.first {
                self?.locationName = placemark.locality ?? "Your Location"
            } else {
                self?.locationName = "Your Location"
            }
        }
    }

    private func fetchWeatherData() {
        guard let latitude = latitude, let longitude = longitude else { return }

        let today = Date()
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: today)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let todayStr = dateFormatter.string(from: today)
        let lastYearStr = dateFormatter.string(from: lastYear)

        let currentWeatherURL = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true"

        let historicalWeatherURL = "https://archive-api.open-meteo.com/v1/archive?latitude=\(latitude)&longitude=\(longitude)&start_date=\(lastYearStr)&end_date=\(lastYearStr)&hourly=temperature_2m"

        // Fetch current weather
        fetchData(from: currentWeatherURL) { [weak self] (data: CurrentWeatherResponse?) in
            DispatchQueue.main.async {
                if let currentWeather = data?.current_weather {
                    self?.currentTemperature = currentWeather.temperature
                    self?.currentWeather = currentWeather
                }
            }
        }

        // Fetch last year's weather
        fetchData(from: historicalWeatherURL) { [weak self] (data: HistoricalWeatherResponse?) in
            DispatchQueue.main.async {
                if let temperature = data?.hourly.temperature_2m.first {
                    self?.lastYearTemperature = temperature
                }
            }
        }
    }

    private func fetchWeeklyComparison() {
        guard let latitude = latitude, let longitude = longitude else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let group = DispatchGroup()

        var comparisons: [WeatherComparison] = []

        for i in 1...7 {
            if let date = Calendar.current.date(byAdding: .day, value: -i, to: Date()),
               let lastYearDate = Calendar.current.date(byAdding: .year, value: -1, to: date) {

                let dateStr = dateFormatter.string(from: date)
                let lastYearDateStr = dateFormatter.string(from: lastYearDate)

                let currentURL = "https://archive-api.open-meteo.com/v1/archive?latitude=\(latitude)&longitude=\(longitude)&start_date=\(dateStr)&end_date=\(dateStr)&hourly=temperature_2m"

                let lastYearURL = "https://archive-api.open-meteo.com/v1/archive?latitude=\(latitude)&longitude=\(longitude)&start_date=\(lastYearDateStr)&end_date=\(lastYearDateStr)&hourly=temperature_2m"

                group.enter()
                var currentTemp: Double?
                var lastYearTemp: Double?

                // Fetch current day's historical data
                fetchData(from: currentURL) { (data: HistoricalWeatherResponse?) in
                    currentTemp = data?.hourly.temperature_2m.first
                    checkCompletion()
                }

                // Fetch last year's data
                fetchData(from: lastYearURL) { (data: HistoricalWeatherResponse?) in
                    lastYearTemp = data?.hourly.temperature_2m.first
                    checkCompletion()
                }

                func checkCompletion() {
                    if let currentTemp = currentTemp, let lastYearTemp = lastYearTemp {
                        let comparison = WeatherComparison(
                            date: date,
                            currentTemp: currentTemp,
                            lastYearTemp: lastYearTemp
                        )
                        comparisons.append(comparison)
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.weeklyComparison = comparisons.sorted { $0.date > $1.date }
        }
    }

    // Generic network request function
    private func fetchData<T: Decodable>(from urlString: String, completion: @escaping (T?) -> Void) {
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else {
                print("Network error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }

            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(decoded)
            } catch {
                print("Decoding error: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
}

// Models
struct CurrentWeatherResponse: Decodable {
    let current_weather: CurrentWeather
}

struct CurrentWeather: Decodable {
    let temperature: Double
    let windspeed: Double
    let winddirection: Double
    var description: String {
        // You can add logic here to determine the weather description based on the data
        return "Sunny" // Placeholder
    }
}

struct HistoricalWeatherResponse: Decodable {
    let hourly: HourlyData
}

struct HourlyData: Decodable {
    let time: [String]
    let temperature_2m: [Double]
}

struct WeatherComparison {
    let date: Date
    let currentTemp: Double
    let lastYearTemp: Double

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
}

// Entry Point
@main
struct TodayLastYearApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
