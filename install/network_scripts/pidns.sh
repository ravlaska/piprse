docker exec pihole bash -c 'echo 192.168.0.3 domainnamesed > /etc/pihole/custom.list'
docker exec pihole bash -c 'echo cname=pihole.domainnamesed,domainnamesed > /etc/dnsmasq.d/05-pihole-custom-cname.conf'
docker exec pihole bash -c 'echo cname=docker.domainnamesed,domainnamesed >> /etc/dnsmasq.d/05-pihole-custom-cname.conf'
