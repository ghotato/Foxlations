package foxtensions.net;

import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.spi.InetAddressResolver;
import java.net.spi.InetAddressResolver.LookupPolicy;
import java.net.spi.InetAddressResolverProvider;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * The iOS Zero JVM's native DNS resolver is broken — getaddrinfo returns the wildcard
 * address (0.0.0.0 with -Djava.net.preferIPv4Stack=true, :: otherwise) instead of real
 * IPs — even though raw TCP works (verified: connect to 1.1.1.1:443 succeeds). This SPI
 * provider (JEP 418, JDK 18+) replaces the platform resolver JVM-wide with DNS-over-HTTPS
 * to Cloudflare at the LITERAL IP 1.1.1.1 — reachable without any DNS, since InetAddress
 * parses literal IPs directly and never calls back into this resolver. Fixes InetAddress
 * and therefore OkHttp's Dns.SYSTEM (which delegates to InetAddress.getAllByName) at once.
 *
 * Registered via META-INF/services/java.net.spi.InetAddressResolverProvider on the app
 * classpath; the JDK loads it through ServiceLoader at InetAddress initialization.
 */
public final class DohResolver extends InetAddressResolverProvider {

    private volatile HttpClient http;
    private final Pattern ipRe =
        Pattern.compile("\"data\"\\s*:\\s*\"(\\d{1,3}(?:\\.\\d{1,3}){3})\"");

    @Override
    public String name() { return "foxtensions-doh"; }

    @Override
    public InetAddressResolver get(Configuration config) {
        final InetAddressResolver builtin = config.builtinResolver();
        return new InetAddressResolver() {
            @Override
            public Stream<InetAddress> lookupByName(String host, LookupPolicy policy)
                    throws UnknownHostException {
                return doh(host);
            }
            @Override
            public String lookupByAddress(byte[] addr) throws UnknownHostException {
                return builtin.lookupByAddress(addr);   // reverse DNS: rarely used, leave to platform
            }
        };
    }

    // Lazily build the HttpClient on first lookup (NOT during the early InetAddress init
    // that runs get()), so we don't touch the networking stack before it's ready.
    private HttpClient http() {
        HttpClient h = http;
        if (h == null) {
            synchronized (this) {
                h = http;
                if (h == null) {
                    h = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(8)).build();
                    http = h;
                }
            }
        }
        return h;
    }

    private Stream<InetAddress> doh(String host) throws UnknownHostException {
        try {
            HttpRequest req = HttpRequest
                .newBuilder(URI.create("https://1.1.1.1/dns-query?type=A&name=" + host))
                .header("accept", "application/dns-json")
                .timeout(Duration.ofSeconds(8))
                .GET().build();
            String body = http().send(req, HttpResponse.BodyHandlers.ofString()).body();
            List<InetAddress> out = new ArrayList<>();
            Matcher m = ipRe.matcher(body);
            while (m.find()) {
                out.add(InetAddress.getByAddress(host, ipv4(m.group(1))));
            }
            if (!out.isEmpty()) return out.stream();
            throw new UnknownHostException("DoH: no A record for " + host);
        } catch (UnknownHostException e) {
            throw e;
        } catch (Exception e) {
            throw new UnknownHostException("DoH failed for " + host + ": " + e);
        }
    }

    private static byte[] ipv4(String ip) {
        String[] p = ip.split("\\.");
        return new byte[] {
            (byte) Integer.parseInt(p[0]), (byte) Integer.parseInt(p[1]),
            (byte) Integer.parseInt(p[2]), (byte) Integer.parseInt(p[3]),
        };
    }
}
