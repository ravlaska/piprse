FROM pihole/pihole:latest
RUN apt update -y && apt install -y unbound

COPY scripts/pihole.conf /etc/unbound/unbound.conf.d/pi-hole.conf
COPY scripts/99-edns.conf /etc/dnsmasq.d/99-edns.conf

RUN mkdir -p /etc/services.d/unbound
COPY scripts/unbound-run /etc/services.d/unbound/run
RUN chmod +x /etc/services.d/unbound/run

ENTRYPOINT ./s6-init
