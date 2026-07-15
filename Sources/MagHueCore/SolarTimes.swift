import Foundation

/// Sunrise/sunset times from latitude, longitude and date, computed locally
/// with the standard NOAA sunrise equation — no network, no CoreLocation.
/// Accurate to about a minute, which is plenty for turning an LED on and off.
public enum SolarTimes {
    public static func events(latitude: Double, longitude: Double,
                              on date: Date, calendar: Calendar)
        -> (sunrise: Date, sunset: Date)? {

        // Julian Day Number for the calendar date at noon UT — an integer, so
        // the time of day comes purely from the equations, not the input.
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let Y = parts.year ?? 2000, M = parts.month ?? 1, D = parts.day ?? 1
        let a = (14 - M) / 12
        let y = Y + 4800 - a
        let m = M + 12 * a - 3
        let jdn = D + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045

        let n = Double(jdn) - 2451545.0 + 0.0008
        // Geographic (east-positive) longitude; solar noon is earlier the
        // further east you are, hence the minus.
        let meanSolarTime = n - longitude / 360.0
        let solarAnomaly = normalize(357.5291 + 0.98560028 * meanSolarTime)
        let anomalyRad = solarAnomaly * .pi / 180

        let center = 1.9148 * sin(anomalyRad)
            + 0.0200 * sin(2 * anomalyRad)
            + 0.0003 * sin(3 * anomalyRad)
        let eclipticLongitude = normalize(solarAnomaly + center + 180 + 102.9372)
        let eclipticRad = eclipticLongitude * .pi / 180

        let transit = 2451545.0 + meanSolarTime
            + 0.0053 * sin(anomalyRad) - 0.0069 * sin(2 * eclipticRad)

        let declinationSin = sin(eclipticRad) * sin(23.44 * .pi / 180)
        let declinationCos = cos(asin(declinationSin))
        let latRad = latitude * .pi / 180

        let hourAngleCos = (sin(-0.833 * .pi / 180) - sin(latRad) * declinationSin)
            / (cos(latRad) * declinationCos)
        guard hourAngleCos >= -1, hourAngleCos <= 1 else { return nil } // polar day/night

        let hourAngle = acos(hourAngleCos) * 180 / .pi
        let sunrise = dateFromJulian(transit - hourAngle / 360.0)
        let sunset = dateFromJulian(transit + hourAngle / 360.0)
        return (sunrise, sunset)
    }

    private static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    private static func dateFromJulian(_ julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2440587.5) * 86400)
    }
}
