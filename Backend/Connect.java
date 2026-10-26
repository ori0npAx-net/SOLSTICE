import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Step 1 of the backend: prove that Java can talk to solar_tracker_db.
 *
 * Run (from the Solar_Tracker_DB folder, with XAMPP's MySQL running):
 *   java -cp "Backend/lib/*" Backend/Connect.java
 */
public class Connect {

    // If you downloaded the MySQL connector instead of the MariaDB one,
    // change "jdbc:mariadb" to "jdbc:mysql" in the line below.
    private static final String URL  = "jdbc:mariadb://localhost:3306/solar_tracker_db?sslMode=disable";
    private static final String USER = "solar_app";
    private static final String PASS = "SolarApp#2026"; // fine for a class project; real systems keep passwords out of code

    public static void main(String[] args) {
        // try-with-resources closes the connection automatically
        try (Connection conn = DriverManager.getConnection(URL, USER, PASS)) {
            System.out.println("Connected to solar_tracker_db!");
            System.out.println();

            // 1) A plain query: list all panels
            System.out.println("All panels:");
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT panel_id, model_name, capacity_watts, status FROM SOLAR_PANEL");
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    System.out.println("  " + rs.getInt("panel_id") + " | "
                            + rs.getString("model_name") + " | "
                            + rs.getBigDecimal("capacity_watts") + " W | "
                            + rs.getString("status"));
                }
            }

            // 2) A query with a parameter (?) - the safe way to use outside values.
            //    The ? is filled in separately, so the value can never be run as SQL.
            //    This is how SQL injection is prevented.
            String wantedStatus = "Active";
            System.out.println();
            System.out.println("Panels with status = " + wantedStatus + ":");
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT model_name, capacity_watts FROM SOLAR_PANEL WHERE status = ?")) {
                ps.setString(1, wantedStatus);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        System.out.println("  " + rs.getString("model_name")
                                + " | " + rs.getBigDecimal("capacity_watts") + " W");
                    }
                }
            }

        } catch (SQLException e) {
            System.out.println("Could not connect or run the query.");
            System.out.println("Message: " + e.getMessage());
            System.out.println("Check: is MySQL green in XAMPP? Did you run 4_app_user.sql? Is the .jar in backend/lib?");
        }
    }
}
