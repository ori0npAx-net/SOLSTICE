import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

/**
 * Pretends to be the solar panel's sensors. Every few seconds it sends one
 * voltage + current reading to the Java server, which saves it in the database.
 * When the real hardware is ready, IT will send the same message instead of this program.
 *
 * Run in a SECOND terminal (the server must already be running):
 *   java -cp "Backend/lib/*" Backend/Simulator.java            -> 20 readings, 2 seconds apart
 *   java Backend/Simulator.java 50 1       -> 50 readings, 1 second apart
 */
public class Simulator {
    public static void main(String[] args) throws Exception {
        int count = args.length > 0 ? Integer.parseInt(args[0]) : 20;
        double delaySeconds = args.length > 1 ? Double.parseDouble(args[1]) : 2;
        int panelId = 1;   // panel 1 is the Active one

        HttpClient client = HttpClient.newHttpClient();
        System.out.println("Simulator started: sending " + count + " readings for panel " + panelId);

        for (int i = 0; i < count; i++) {
            // Imitate a day: the sun rises and sets, so power follows a smooth hill shape (sine curve)
            double sun = Math.sin(Math.PI * i / Math.max(1, count - 1));      // 0 -> 1 -> 0
            double voltage = 17.0 + 3.0 * sun + (Math.random() - 0.5) * 0.4;  // about 17 to 20 V
            double current = 0.2 + 5.0 * sun + (Math.random() - 0.5) * 0.2;   // about 0.2 to 5 A
            current = Math.max(0, current);

            String body = String.format("panel=%d&voltage=%.2f&current=%.2f", panelId, voltage, current);
            HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:8080/api/readings"))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            System.out.println("Sent " + body + "  ->  server says " + response.statusCode() + " " + response.body());
            Thread.sleep((long) (delaySeconds * 1000));
        }
        System.out.println("Simulator finished.");
    }
}
