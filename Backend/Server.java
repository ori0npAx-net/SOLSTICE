import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.*;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;

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
 *   /api/panels            simulation field panels with latest received power
 *   /api/summary           per-panel statistics filtered by date and clock
 *   /api/days              dates with saved field readings
 *   /api/simulation-state  append-only calendar/weather/soil checkpoints
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

        server.createContext("/dashboard.js", ex -> {
            if (!isGet(ex)) return;
            try { sendBytes(ex,200,"text/javascript; charset=utf-8",Files.readAllBytes(Path.of("Backend/web/dashboard.js"))); }
            catch(IOException e) { send(ex,404,"text/plain","Not found"); }
        });

        server.createContext("/api/panels", ex -> {
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT p.panel_id, p.model_name, p.capacity_watts, p.status, "
                    + "e.power_output_w AS latest_power_w, COALESCE(e.simulated_at,e.recorded_at) AS last_recorded_at, "
                    + "e.recorded_at AS received_at, e.simulated_at "
                    + "FROM SOLAR_PANEL p LEFT JOIN ENERGY_READING e ON e.reading_id = "
                    + "(SELECT e2.reading_id FROM ENERGY_READING e2 WHERE e2.panel_id = p.panel_id "
                    + "ORDER BY e2.reading_id DESC LIMIT 1) WHERE p.is_simulation = TRUE ORDER BY p.model_name");
        });

        server.createContext("/api/health", ex -> {
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT 'connected' AS database_status, "
                    + "(SELECT COUNT(*) FROM SUN_SENSOR) AS sensor_records, "
                    + "(SELECT COUNT(*) FROM MOVEMENT_LOG) AS movement_records");
        });

        server.createContext("/api/summary", ex -> {
            if (!isGet(ex)) return;
            String date = validDate(ex);
            if (date == null) return;
            String range = clockFilter(ex,"e.") + (date.isEmpty() ? "" : " AND COALESCE(e.simulated_at,e.recorded_at) >= ? AND COALESCE(e.simulated_at,e.recorded_at) < ?");
            String sql = "SELECT p.panel_id,p.model_name,p.status,MAX(e.power_output_w) AS peak_power_w,ROUND(AVG(e.power_output_w),2) AS average_power_w,COUNT(e.reading_id) AS reading_count FROM SOLAR_PANEL p LEFT JOIN ENERGY_READING e ON e.panel_id=p.panel_id" + range + " WHERE p.is_simulation=TRUE GROUP BY p.panel_id,p.model_name,p.status ORDER BY p.model_name";
            if (date.isEmpty()) sendQuery(ex, sql);
            else sendQuery(ex, sql, date, LocalDate.parse(date).plusDays(1).toString());
        });

        server.createContext("/api/days", ex -> {
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT DATE(COALESCE(e.simulated_at,e.recorded_at)) AS day,COUNT(*) AS reading_count FROM ENERGY_READING e JOIN SOLAR_PANEL p ON p.panel_id=e.panel_id WHERE p.is_simulation=TRUE" + clockFilter(ex,"e.") + " GROUP BY day ORDER BY day DESC");
        });

        server.createContext("/api/simulation-state", ex -> {
            if (ex.getRequestMethod().equals("POST")) { saveState(ex); return; }
            if (!isGet(ex)) return;
            sendQuery(ex, "SELECT snapshot_id,simulated_at,state_json,saved_at FROM SIMULATION_STATE ORDER BY snapshot_id DESC LIMIT 1");
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
            String date = validDate(ex);
            if (date == null) return;
            String sql = "SELECT reading_id,recorded_at,simulated_at,COALESCE(simulated_at,recorded_at) AS reading_time,voltage_v,current_a,power_output_w,cloud_cover,rain_intensity,dust_level,bird_level FROM ENERGY_READING WHERE panel_id=?" + clockFilter(ex, "");
            if (date.isEmpty()) sendQuery(ex, sql + " ORDER BY reading_time,reading_id", panelId);
            else sendQuery(ex, sql + " AND COALESCE(simulated_at,recorded_at)>=? AND COALESCE(simulated_at,recorded_at)<? ORDER BY reading_time,reading_id", panelId, date, LocalDate.parse(date).plusDays(1).toString());
        });

        server.start();
        System.out.println("Server running. Open http://localhost:" + PORT + " in Chrome.");
        System.out.println("Press Ctrl+C in this terminal to stop it.");
    }

    /**
     * SAVING a reading. The simulator (later: the real sensor) sends:
     *   POST /api/readings      body:  panel=1&voltage=18.5&current=3.2
     * We check the numbers, then INSERT one row into ENERGY_READING.
     * power_output_w is calculated by the database. recorded_at is reception time;
     * optional simulated_at and weather fields retain the simulation's own clock.
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
        Timestamp simulated;
        Double[] weather = new Double[4];
        try {
            simulated = parseTimestamp(queryParam(body, "simulated_at"));
            String[] names = {"cloud_cover","rain_intensity","dust_level","bird_level"};
            for (int i=0;i<names.length;i++) {
                String value = queryParam(body,names[i]);
                if (value != null) {
                    weather[i] = Double.valueOf(value);
                    if (!(weather[i]>=0 && weather[i]<=1)) throw new IllegalArgumentException();
                }
            }
        } catch (IllegalArgumentException e) {
            send(ex,400,"application/json","{\"error\":\"invalid simulated timestamp or weather (0-1 required)\"}"); return;
        }
        String sql = "INSERT INTO ENERGY_READING (panel_id,voltage_v,current_a,simulated_at,cloud_cover,rain_intensity,dust_level,bird_level) VALUES (?,?,?,?,?,?,?,?)";
        try (Connection conn = DriverManager.getConnection(URL, USER, PASS);
             PreparedStatement ps = conn.prepareStatement(sql,Statement.RETURN_GENERATED_KEYS)) {
            ps.setInt(1, panelId);
            ps.setDouble(2, voltage);
            ps.setDouble(3, current);
            ps.setTimestamp(4, simulated);
            for (int i=0;i<4;i++) ps.setObject(5+i,weather[i]);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                keys.next();
                send(ex, 201, "application/json", "{\"saved\":true,\"reading_id\":" + keys.getLong(1) + "}");
            }
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

    private static Timestamp parseTimestamp(String value) {
        if (value == null || value.isBlank()) return null;
        try {
            LocalDateTime dt = LocalDateTime.parse(value.replace(' ', 'T'));
            if (dt.getYear()<2020 || dt.getYear()>2100) throw new IllegalArgumentException();
            return Timestamp.valueOf(dt);
        } catch (DateTimeParseException e) { throw new IllegalArgumentException(e); }
    }

    private static String validDate(HttpExchange ex) throws IOException {
        String value = queryParam(ex.getRequestURI().getRawQuery(), "date");
        if (value == null || value.isBlank()) return "";
        try {
            LocalDate date=LocalDate.parse(value);
            if(date.getYear()<2020 || date.getYear()>2100) throw new DateTimeParseException("date out of range",value,0);
            return date.toString();
        }
        catch (DateTimeParseException e) { send(ex,400,"application/json","{\"error\":\"date must be YYYY-MM-DD\"}"); return null; }
    }

    private static String clockFilter(HttpExchange ex, String prefix) {
        String clock = queryParam(ex.getRequestURI().getRawQuery(),"clock");
        if ("simulation".equals(clock)) return " AND " + prefix + "simulated_at IS NOT NULL";
        if ("legacy".equals(clock)) return " AND " + prefix + "simulated_at IS NULL";
        return "";
    }

    private static void saveState(HttpExchange ex) throws IOException {
        byte[] bytes = ex.getRequestBody().readNBytes(131073);
        if (bytes.length>131072) { send(ex,413,"application/json","{\"error\":\"state too large\"}"); return; }
        String body = new String(bytes,StandardCharsets.UTF_8);
        String json = queryParam(body,"state");
        Timestamp time;
        try {
            time = parseTimestamp(queryParam(body,"simulated_at"));
            if (time==null || json==null || !json.startsWith("{") || !json.endsWith("}")) throw new IllegalArgumentException();
        } catch (IllegalArgumentException e) { send(ex,400,"application/json","{\"error\":\"need timestamp and state object\"}"); return; }
        try (Connection conn=DriverManager.getConnection(URL,USER,PASS);
             PreparedStatement ps=conn.prepareStatement("INSERT INTO SIMULATION_STATE(simulated_at,state_json) VALUES (?,?)")) {
            ps.setTimestamp(1,time); ps.setString(2,json); ps.executeUpdate();
            send(ex,201,"application/json","{\"saved\":true}");
        } catch(SQLException e) { send(ex,500,"application/json","{\"error\":\"could not save simulation state\"}"); }
    }

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
            if (kv.length == 2 && kv[0].equals(name)) return URLDecoder.decode(kv[1],StandardCharsets.UTF_8);
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
