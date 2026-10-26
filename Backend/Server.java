import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.*;

/**
 * Step 2 of the backend: a tiny web server.
 *
 * Run (from the Solar_Tracker_DB folder, with XAMPP's MySQL running):
 *   java -cp "Backend/lib/*" Backend/Server.java
 * Then open  http://localhost:8080  in Chrome.
 *
 * Pages / endpoints:
 *   /                      the web page (Backend/web/index.html)
 *   /settings              palette settings page (Backend/web/settings.html)
 *   /api/health            database connection and sensor / movement counts
 *   /api/panels            all panels, with latest saved power, as JSON
 *   /api/summary           peak and average power per panel (the panel_performance view)
 *   /api/readings?panel=1  power readings of one panel (GET = read)
 *   /api/readings          POST = save a new reading (used by the simulator / sensor)
 */
public class Server {

    private static final String URL  = "jdbc:mariadb://localhost:3306/solar_tracker_db?sslMode=disable";
    private static final String USER = "solar_app";
    private static final String PASS = "SolarApp#2026";
    private static final int PORT = 8080;

    public static void main(String[] args) throws IOException {
        // 127.0.0.1 = only THIS computer can reach the server (nobody else on the network)
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", PORT), 0);

        server.createContext("/", ex -> {
            if (!ex.getRequestURI().getPath().equals("/")) { send(ex, 404, "text/plain", "Not found"); return; }
            if (!isGet(ex)) return;
            try {
                byte[] page = Files.readAllBytes(Path.of("Backend/web/index.html"));
                sendBytes(ex, 200, "text/html; charset=utf-8", page);
            } catch (IOException e) {
                send(ex, 500, "text/plain", "Could not find Backend/web/index.html");
            }
        });

        server.createContext("/settings", ex -> {
            if (!ex.getRequestURI().getPath().equals("/settings")
                    && !ex.getRequestURI().getPath().equals("/settings/")) {
                send(ex, 404, "text/plain", "Not found"); return;
            }
            if (!isGet(ex)) return;
            try {
                byte[] page = Files.readAllBytes(Path.of("Backend/web/settings.html"));
                sendBytes(ex, 200, "text/html; charset=utf-8", page);
            } catch (IOException e) {
                send(ex, 500, "text/plain", "Could not find Backend/web/settings.html");
            }
        });

        server.createContext("/api/panels", ex -> {
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT p.panel_id, p.model_name, p.capacity_watts, p.status, "
                    + "e.power_output_w AS latest_power_w, e.recorded_at AS last_recorded_at "
                    + "FROM SOLAR_PANEL p LEFT JOIN ENERGY_READING e ON e.reading_id = "
                    + "(SELECT e2.reading_id FROM ENERGY_READING e2 WHERE e2.panel_id = p.panel_id "
                    + "ORDER BY e2.recorded_at DESC, e2.reading_id DESC LIMIT 1) ORDER BY p.panel_id");
        });

        server.createContext("/api/health", ex -> {
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT 'connected' AS database_status, "
                    + "(SELECT COUNT(*) FROM SUN_SENSOR) AS sensor_records, "
                    + "(SELECT COUNT(*) FROM MOVEMENT_LOG) AS movement_records");
        });

        server.createContext("/api/summary", ex -> {
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT model_name, status, peak_power_w, average_power_w FROM panel_performance");
        });

        server.createContext("/api/readings", ex -> {
            String method = ex.getRequestMethod();
            if (method.equals("POST")) { saveReading(ex); return; }   // the sensor / simulator SAVES a reading
            if (!isGet(ex)) return;                                    // everything else except GET is refused
            String panelText = queryParam(ex.getRequestURI().getQuery(), "panel");
            int panelId;
            try {
                panelId = Integer.parseInt(panelText);   // only a whole number is accepted
            } catch (NumberFormatException e) {
                send(ex, 400, "application/json", "{\"error\":\"panel must be a number\"}");
                return;
            }
            // The ? is filled in safely, so the value can never be run as SQL (prevents SQL injection)
            sendQuery(ex,
                "SELECT recorded_at, voltage_v, current_a, power_output_w "
              + "FROM ENERGY_READING WHERE panel_id = ? ORDER BY recorded_at", panelId);
        });

        server.start();
        System.out.println("Server running. Open http://localhost:" + PORT + " in Chrome.");
        System.out.println("Press Ctrl+C in this terminal to stop it.");
    }

    /**
     * SAVING a reading. The simulator (later: the real sensor) sends:
     *   POST /api/readings      body:  panel=1&voltage=18.5&current=3.2
     * We check the numbers, then INSERT one row into ENERGY_READING.
     * power_output_w is calculated by the database itself, and the time is added automatically.
     */
    private static void saveReading(HttpExchange ex) throws IOException {
        String body = new String(ex.getRequestBody().readNBytes(1000), StandardCharsets.UTF_8); // max 1000 bytes
        int panelId;
        double voltage, current;
        try {
            panelId = Integer.parseInt(queryParam(body, "panel"));
            voltage = Double.parseDouble(queryParam(body, "voltage"));
            current = Double.parseDouble(queryParam(body, "current"));
        } catch (NumberFormatException | NullPointerException e) {
            send(ex, 400, "application/json", "{\"error\":\"need numbers: panel, voltage, current\"}");
            return;
        }
        // Sensible limits for one panel (also rejects NaN, which fails both comparisons)
        if (!(voltage >= 0 && voltage <= 60) || !(current >= 0 && current <= 20)) {
            send(ex, 400, "application/json", "{\"error\":\"voltage must be 0-60 and current 0-20\"}");
            return;
        }
        String sql = "INSERT INTO ENERGY_READING (panel_id, voltage_v, current_a) VALUES (?, ?, ?)";
        try (Connection conn = DriverManager.getConnection(URL, USER, PASS);
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, panelId);
            ps.setDouble(2, voltage);
            ps.setDouble(3, current);
            ps.executeUpdate();
            send(ex, 201, "application/json", "{\"saved\":true}");
        } catch (SQLException e) {
            System.out.println("Database error: " + e.getMessage());
            if ("23000".equals(e.getSQLState())) {   // foreign key: that panel does not exist
                send(ex, 400, "application/json", "{\"error\":\"unknown panel\"}");
            } else {
                send(ex, 500, "application/json", "{\"error\":\"database error\"}");
            }
        }
    }

    // ---------- helpers ----------

    /** Runs a SELECT and sends the rows back as a JSON list. */
    private static void sendQuery(HttpExchange ex, String sql, Object... params) throws IOException {
        try (Connection conn = DriverManager.getConnection(URL, USER, PASS);
             PreparedStatement ps = conn.prepareStatement(sql)) {
            for (int i = 0; i < params.length; i++) ps.setObject(i + 1, params[i]);
            try (ResultSet rs = ps.executeQuery()) {
                send(ex, 200, "application/json; charset=utf-8", toJson(rs));
            }
        } catch (SQLException e) {
            System.out.println("Database error: " + e.getMessage());   // details stay in the terminal
            send(ex, 500, "application/json", "{\"error\":\"database error\"}"); // user sees nothing sensitive
        }
    }

    /** Turns a ResultSet into JSON text like [{"panel_id":1,"model_name":"SunMax 300W"}, ...] */
    private static String toJson(ResultSet rs) throws SQLException {
        ResultSetMetaData md = rs.getMetaData();
        StringBuilder sb = new StringBuilder("[");
        boolean firstRow = true;
        while (rs.next()) {
            if (!firstRow) sb.append(",");
            firstRow = false;
            sb.append("{");
            for (int c = 1; c <= md.getColumnCount(); c++) {
                if (c > 1) sb.append(",");
                sb.append("\"").append(escape(md.getColumnLabel(c))).append("\":");
                Object v = rs.getObject(c);
                if (v == null) sb.append("null");
                else if (v instanceof Number) sb.append(v);
                else if (v instanceof Timestamp) sb.append("\"").append(v.toString().replaceAll("\\.0$", "")).append("\"");
                else sb.append("\"").append(escape(v.toString())).append("\"");
            }
            sb.append("}");
        }
        return sb.append("]").toString();
    }

    private static String escape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
    }

    private static String queryParam(String query, String name) {
        if (query == null) return null;
        for (String pair : query.split("&")) {
            String[] kv = pair.split("=", 2);
            if (kv.length == 2 && kv[0].equals(name)) return kv[1];
        }
        return null;
    }

    /** The website only READS data, so every other method (POST, DELETE ...) is refused. */
    private static boolean isGet(HttpExchange ex) throws IOException {
        if (ex.getRequestMethod().equals("GET")) return true;
        send(ex, 405, "text/plain", "Method not allowed");
        return false;
    }

    private static void send(HttpExchange ex, int status, String type, String body) throws IOException {
        sendBytes(ex, status, type, body.getBytes(StandardCharsets.UTF_8));
    }

    private static void sendBytes(HttpExchange ex, int status, String type, byte[] bytes) throws IOException {
        ex.getResponseHeaders().set("Content-Type", type);
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) { os.write(bytes); }
    }
}
