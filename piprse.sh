#!/bin/sh


# Define which user is running this script
USER=${SUDO_USER:-$(who -m | awk '{ print $1 }')}

# Define path to this script
SDIR=$(dirname -- "$( readlink -f -- "$0"; )";)

# Check if script is running as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run with root privileges. Try 'sudo ./piprse.sh'\n"
  exit 1
fi

# Check nginx repair
check_proxy() {
  if [ ! "$(docker ps | grep nginx)" ]; then
    return 0
  else
    docker restart nginx
  fi
}

# Stop a container if it's running
container_stopper() {
  if [ "$(docker ps | grep $1)" ]; then 
    docker stop $1
  fi
}

# Remove all piprse contents
uninstall() {
  whiptail --yesno "Do you want to uninstall whole piprse?" 20 60 2
  if [ $? -eq 0 ]; then
    container_stopper "pihole"
    container_stopper "wireguard"
    container_stopper "ddns"
    container_stopper "nginx"
    container_stopper "portainer"
    container_stopper "watchtower"
    container_stopper "hpot"
    sudo rm -r /home/$USER/piprse
    docker system prune -a -f
    whiptail --msgbox "Everything from piprse was removed. $()" 20 70 1
    return 0
  else
    return 0
  fi
  
}

# Check if container is running
check_run() {
  if [ ! "$(docker ps | grep $1)" ]; then
    whiptail --msgbox "The $1 is not running. Check 'docker logs $1' to investigate errors. $()" 20 70 1
    return 0
  else
    whiptail --msgbox "The $1 container is running. $()" 20 70
    return 0
  fi
}

# Whiptail size handler
size_window() {
  W_HEIGHT=18
  W_WIDTH=$(tput cols)

  if [ -z "$W_WIDTH" ] || [ "$W_WIDTH" -lt 60 ]; then
    W_WIDTH=80
  fi
  if [ "$W_WIDTH" -gt 178 ]; then
    W_WIDTH=120
  fi
  W_MENU_HEIGHT=$(($W_HEIGHT-7))
}

# Removing docker's unused stuff
docker_prune() {
  whiptail --yesno "Do you want to remove all unused Docker's stuff?" 20 60 2
  if [ $? -eq 0 ]; then
    docker system prune -a -f
    return 0
  fi
  return 0
}

# Pihole updater (pulling new imgage from docker hub and rebuilding container)
update_pihole() {
  docker-compose --env-file=/home/$USER/piprse/pihole_vpn/.env -f /home/$USER/piprse/pihole_vpn/docker-compose.yml up -d --build pihole
  docker system prune -a -f
  return 0
}

# Check the number of ssh port if != 22 then go to change menu
check_ssh() {
  SSHA=$(cat /etc/ssh/sshd_config | grep "Port " | grep -o ' .*')
  if [ $SSHA -eq 22 ]; then
    whiptail --msgbox "\
    To install HoneyPot the ssh port
    needs to be different than 22

    Please change the port number.
      $()\
    " 20 70 1
    return 0
  fi
  setup_tarpit
  return 0
}

# Installing tarpit container
setup_tarpit() {
  mkdir /home/$USER/piprse/security/honeypot -p
  cp $SDIR/install/hpot-compose.yml /home/$USER/piprse/security/docker-compose.yml
  get_timezone
  echo TIMEZONE=TIMEZONE_SED > /home/$USER/piprse/security/.env
  whiptail --yesno "Your timezone is to: $TZ Do you want to proceed?" 20 60 2
  if [ $? -eq 0 ]; then
    sed -i 's+TIMEZONE_SED+'$TZ'+g' /home/$USER/piprse/security/.env
    docker-compose --env-file=/home/$USER/piprse/security/.env -f /home/$USER/piprse/security/docker-compose.yml up -d hpot
    check_run "hpot"
    return 0
  else
    return 0
  fi 
}

# About Window
about() {
  whiptail --title About --msgbox "\
  Pi Private Server tool was created by Rafał Laska
  as an Engineering Thesis Project.

  Feel free to fork, report issues, etc.
  https://github.com/ravlaska/piprse
  $()\
  " 20 70 1
  return 0
}

# Basic instruction
instruction() {
  SSHA=$(cat /etc/ssh/sshd_config | grep "Port " | grep -o ' .*')
  whiptail --title Instruction --msgbox "\
  This tool was created for setup privacy-enhancing server with ease.

  It was tested on the Raspberry Pi 4, but should work on most devices with Raspbian system.

  Most important info:

  Adresses (adresses with domain only while reverse proxy is ON)
  - pihole:     pihole.yourdomain   device_lan_ip:81/admin
  - portainer:  docker.yourdomain   device_lan_ip:9000

  - Wachtower is updating all the installed conatiners, except for pihole!

  - Your current SSH port: $SSHA
  $()\
  " 20 80 1
  return 0
}

# Changing port of the SSH
config_ssh() {
  PORTS=$(sudo lsof -i -P -n | grep LISTEN | grep -o ':.*' | cut -d: -f2 | sed 's#(.*$##g' | xargs | sed -e 's/ /, /g')
  SSHP=$(whiptail --inputbox "\
    Enter new port number for the SSH: 
    Value must be between [1024-65536],
    but can't be [5335], [8000], [8080], [9000], [9443], [51820].

    Port cannot be used by any service in this device,
    here is the generated list of used ports:\n $PORTS" 20 60 3>&1 1>&2 2>&3)
  exitstatus=$?
  if [ $exitstatus = 0 ]; then
    sed -i '/Port /c\Port '$SSHP /etc/ssh/sshd_config
    service sshd restart
    whiptail --msgbox "\
    SSH port has been changed to $SSHP
    $()\
    " 20 60 1
    return 0
  else
    return 0
  fi
}

# Initial setup of Docker & Docker-Compose
setup_initial() {
  sudo apt update -y
  sudo apt upgrade -y
  
  sudo raspi-config nonint do_expand_rootfs
  sudo raspi-config nonint do_boot_behaviour B2

  sudo rm -r /etc/profile.d/*
  sudo cp install/motd /etc/profile.d/motd.sh
  sudo chmod +x /etc/profile.d/motd.sh
  sudo service sshd restart
  
  sudo apt install raspberrypi-kernel raspberrypi-kernel-headers -y
  curl -sSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  sudo apt install docker-compose -y

  whiptail --yesno "\
  System must be rebooted. 
  Would you like to reboot now?
  " 20 60 2
  if [ $? -eq 0 ]; then
    reboot
  fi
  return 0
}

# =============================================================================================================
# PIHOLE_VPN SETUP MENU
# =============================================================================================================
menu_pihole_vpn() {
MENU=$(whiptail --title "Pihole_VPN stack setup" --menu "Pihole_VPN stack setup" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
  "1 Full setup" "Install <Pihole + Unbound DNS + Wireguard VPN> stack [VPN requires domain]" \
  "2 Pihole with Unbound DNS setup" "Install <Pihole + Unbound DNS> only" \
  3>&1 1>&2 2>&3)
RET=$?
    if [ $RET -eq 1 ]; then
      return 0
    elif [ $RET -eq 0 ]; then
      case "$MENU" in
        1\ *) setup_full_pihole_vpn ;;
        2\ *) setup_pihole_only ;;
        *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
      esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
    fi
}

# Setup pihole with wireguard stack
setup_full_pihole_vpn() {
  sudo apt install qrencode -y
  mkdir /home/$USER/piprse/pihole_vpn -p
  mkdir /home/$USER/piprse/pihole_vpn/pihole/dns -p
  mkdir /home/$USER/piprse/pihole_vpn/pihole/lighttpd -p
  cp $SDIR/install/pihole_vpn-compose.yml /home/$USER/piprse/pihole_vpn/docker-compose.yml
  cp $SDIR/install/pihole_scripts /home/$USER/piprse/pihole_vpn/scripts -r
  echo 'nameserver 127.0.0.1' > /home/$USER/piprse/pihole_vpn/pihole/dns/resolv.conf
  echo 'nameserver 1.1.1.1' >> /home/$USER/piprse/pihole_vpn/pihole/dns/resolv.conf
  vars_pihole_vpn
  mv /home/$USER/piprse/pihole_vpn/scripts/external.conf /home/$USER/piprse/pihole_vpn/pihole/lighttpd/external.conf
  vars_wireguard
  docker-compose --env-file=/home/$USER/piprse/pihole_vpn/.env -f /home/$USER/piprse/pihole_vpn/docker-compose.yml up -d --build
  docker restart pihole wireguard
  docker system prune -a -f
  check_proxy
  check_run "pihole"
  check_run "wireguard"
  return 0
}

# Setup pihole/dns container only (pihole.yourdomain)
setup_pihole_only() {
  mkdir /home/$USER/piprse/pihole_vpn -p
  mkdir /home/$USER/piprse/pihole_vpn/pihole/dns -p
  mkdir /home/$USER/piprse/pihole_vpn/pihole/lighttpd -p
  cp $SDIR/install/pihole_vpn-compose.yml /home/$USER/piprse/pihole_vpn/docker-compose.yml
  cp $SDIR/install/pihole_scripts /home/$USER/piprse/pihole_vpn/scripts -r
  echo 'nameserver 127.0.0.1' > /home/$USER/piprse/pihole_vpn/pihole/dns/resolv.conf
  echo 'nameserver 1.1.1.1' >> /home/$USER/piprse/pihole_vpn/pihole/dns/resolv.conf
  vars_pihole_vpn
  mv /home/$USER/piprse/pihole_vpn/scripts/external.conf /home/$USER/piprse/pihole_vpn/pihole/lighttpd/external.conf
  docker-compose --env-file=/home/$USER/piprse/pihole_vpn/.env -f /home/$USER/piprse/pihole_vpn/docker-compose.yml up -d --build pihole
  docker restart pihole
  docker system prune -a -f
  check_proxy
  check_run "pihole"
  return 0
}

# =============================================================================================================
# MANAGEMENT SETUP MENU
# =============================================================================================================
menu_management() {
MENU=$(whiptail --title "Management stack setup" --menu "Management stack setup" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
  "1 Full setup" "Install <Portainer + Watchtower> stack" \
  "2 Portainer setup" "Install <Portainer> only" \
  "3 Watchtower setup" "Install <Watchtower> only 
  [Pihole with Unbound DNS conatiner is excluded from Watchtower updates !]"\
  3>&1 1>&2 2>&3)
RET=$?
    if [ $RET -eq 1 ]; then
      return 0
    elif [ $RET -eq 0 ]; then
      case "$MENU" in
        1\ *) setup_full_management ;;
        2\ *) setup_portainer ;;
        3\ *) setup_watchtower ;;
        *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
      esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
    fi
}
 
# Setup portainer container (docker.yourdomain)
setup_portainer() {
  mkdir /home/$USER/piprse/mgmt -p
  cp $SDIR/install/mgmt-compose.yml /home/$USER/piprse/mgmt/docker-compose.yml
  get_timezone
  echo TIMEZONE=TIMEZONE_SED > /home/$USER/piprse/mgmt/.env
  whiptail --yesno "Your timezone is to: $TZ Do you want to proceed?" 20 60 2
  if [ $? -eq 0 ]; then
    sed -i 's+TIMEZONE_SED+'$TZ'+g' /home/$USER/piprse/mgmt/.env
    docker-compose --env-file=/home/$USER/piprse/mgmt/.env -f /home/$USER/piprse/mgmt/docker-compose.yml up -d portainer
    docker restart portainer
    check_proxy
    check_run "portainer"
  else
    return 0
  fi
}

# Setup watchtower container
setup_watchtower() {
  mkdir /home/$USER/piprse/mgmt -p
  touch /home/$USER/piprse/mgmt/config.json
  cp $SDIR/install/mgmt-compose.yml /home/$USER/piprse/mgmt/docker-compose.yml
  get_timezone
  echo TIMEZONE=TIMEZONE_SED > /home/$USER/piprse/mgmt/.env
  whiptail --yesno "Your timezone is to: $TZ Do you want to proceed?" 20 60 2
  if [ $? -eq 0 ]; then
    sed -i 's+TIMEZONE_SED+'$TZ'+g' /home/$USER/piprse/mgmt/.env
    docker-compose --env-file=/home/$USER/piprse/mgmt/.env -f /home/$USER/piprse/mgmt/docker-compose.yml up -d watchtower
    docker restart watchtower
    check_proxy
    check_run "watchtower"
    return 0
  else
    return 0
  fi
}

# Setup full management stack
setup_full_management() {
  setup_portainer
  setup_watchtower
  return 0
}

# =============================================================================================================
# NETWORK SETUP MENU
# =============================================================================================================
menu_network() {
MENU=$(whiptail --title "Network stack setup" --menu "Network stack setup" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
  "1 Full setup" "Install <Dynamic DNS (ddclient) + Reverse Proxy (nginx)> stack" \
  "2 Reverse proxy setup" "Install <nginx> only" \
  "3 Dynamic DNS setup" "Install <ddclient-dnsomatic> only"\
  3>&1 1>&2 2>&3)
RET=$?
    if [ $RET -eq 1 ]; then
      return 0
    elif [ $RET -eq 0 ]; then
      case "$MENU" in
        1\ *) setup_full_network ;;
        2\ *) setup_rproxy ;;
        3\ *) setup_ddns ;;
        *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
      esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
    fi
}

# Setup reverse proxy - nginx
setup_rproxy() {
  mkdir /home/$USER/piprse/network/nginx -p
  mkdir /home/$USER/piprse/network/ssl -p
  openssl req -x509 -newkey rsa:4096 -keyout /home/$USER/piprse/network/ssl/key.pem -out /home/$USER/piprse/network/ssl/cert.pem -sha256 -days 10000 -nodes -subj '/CN=localhost'
  cp $SDIR/install/network-compose.yml /home/$USER/piprse/network/docker-compose.yml
  cp $SDIR/install/network_scripts/pidns.sh /home/$USER/piprse/network/pidns.sh
  cp $SDIR/install/network_scripts/nginx.conf /home/$USER/piprse/network/nginx/nginx.conf
  vars_nginx
  get_timezone
  echo TIMEZONE=TIMEZONE_SED > /home/$USER/piprse/network/.env
  whiptail --yesno "Your timezone is to: $TZ Do you want to proceed?" 20 60 2
  if [ $? -eq 0 ]; then
    sed -i 's+TIMEZONE_SED+'$TZ'+g' /home/$USER/piprse/network/.env
    chmod +x /home/$USER/piprse/network/pidns.sh
    sudo bash /home/$USER/piprse/network/pidns.sh
    docker-compose --env-file=/home/$USER/piprse/network/.env -f /home/$USER/piprse/network/docker-compose.yml up -d nginx
    docker restart nginx

    if [ "$(docker ps | grep pihole)" ]; then
      docker restart pihole
    fi

    if [ "$(docker ps | grep portainer)" ]; then
      docker restart portainer
    fi

    check_run "nginx"
  else
    return 0
  fi
}

# Setup dynamic DNS - ddclient (dnsomatic)
setup_ddns() {
  mkdir /home/$USER/piprse/network/ddns -p
  cp $SDIR/install/network-compose.yml /home/$USER/piprse/network/docker-compose.yml
  cp $SDIR/install/network_scripts/ddclient.conf /home/$USER/piprse/network/ddns/ddclient.conf
  vars_ddns
  get_timezone
  echo TIMEZONE=TIMEZONE_SED > /home/$USER/piprse/network/.env
  whiptail --yesno "Your timezone is to: $TZ Do you want to proceed?" 20 60 2
  if [ $? -eq 0 ]; then
    sed -i 's+TIMEZONE_SED+'$TZ'+g' /home/$USER/piprse/network/.env
    docker-compose --env-file=/home/$USER/piprse/network/.env -f /home/$USER/piprse/network/docker-compose.yml up -d ddns
    docker restart ddns
    check_run "ddns"
    return 0
  fi
  return 0
}

# Setup whole network stack
setup_full_network() {
  setup_ddns
  setup_rproxy
  return 0
}

# =============================================================================================================
# ADDITIONAL SETUP MENU
# =============================================================================================================
menu_powersave() {
MENU=$(whiptail --title "Powersave options" --menu "Powersave options" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
  "1 <OFF> Wi-Fi" "Disable Wi-Fi to lower power consupmtion" \
  "2 <OFF> Bluetooth" "Disable Bluetooth to lower power consumption" \
  "3 <ON> Wi-Fi and Bluetooth" "Turn on Wi-Fi and Bluetooth"\
  3>&1 1>&2 2>&3)
RET=$?
    if [ $RET -eq 1 ]; then
      return 0
    elif [ $RET -eq 0 ]; then
      case "$MENU" in
        1\ *) disable_wifi ;;
        2\ *) disable_bluetooth ;;
        3\ *) enable_wibt ;;
        *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
      esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
    fi
}

# Turn wifi off (write into /boot/config.txt)
disable_wifi() {
  sudo echo "dtoverlay=disable-wifi" >> /boot/config.txt
  whiptail --msgbox "Wi-Fi will be disabled after rebooting this device" 20 60 1
  return 0
}

# Turn bluetooth off (write into /boot/config.txt)
disable_bluetooth() {
  sudo echo "dtoverlay=disable-bt" >> /boot/config.txt
  whiptail --msgbox "Bluetooth will be disabled after rebooting this device" 20 60 1
  return 0
}

# Turn wifi & bluetooth on (write into /boot/config.txt)
enable_wibt() {
  sudo sed '/dtoverlay=disable-bt\|dtoverlay=disable-wifi/d' /boot/config.txt
  whiptail --msgbox "Wi-Fi & Bluetooth will be enabled after rebooting this device" 20 60 1
  return 0
}

# =============================================================================================================
# SYSTEM UPDATE
# =============================================================================================================
update_system() {
  whiptail --title "Important information" --msgbox "\
  System will be updated and upgraded right now.

  If the kernel update option will appear, 
  please ignore it and select 'cancel'.
    $()\
  " 20 70 1

  apt update -y
  apt upgrade -y
  whiptail --yesno "Do you want to reboot system now?" 20 60 2
    if [ $? -eq 0 ]; then
        reboot
    fi
  return 0
}

# =============================================================================================================
# CLEANING LOGS
# =============================================================================================================
cleaning_dlogs() {
    CONTAINER_LOG=$(whiptail --inputbox "Which container's logs you want to clean?" 20 60 3>&1 1>&2 2>&3)
    sudo sh -c echo "" > $(docker inspect --format="{{.LogPath}}" ${CONTAINER_LOG})
    #whiptail --msgbox "${CONTAINER_LOG} logs cleaned!" 20 60 1
    exitstatus=$?
    if [ $exitstatus = 0 ]; then
        whiptail --msgbox "${CONTAINER_LOG} logs cleaned!" 20 60 1
    else
        whiptail --msgbox "Error while cleaning logs! [check container name]" 20 60 1
    fi
}

# =============================================================================================================
# CHANGE ENV VARIABLES
# =============================================================================================================
# Configuring timezone in the device's system
config_timezone() {
    dpkg-reconfigure tzdata
    return 0
}

# Get current timezone from the device's system
get_timezone() {
  TZ=$(timedatectl show --property=Timezone | grep -oP '(?<=Timezone=).*')
}

# Copying pihole's .evn file 
copy_env_file() {
  cp $SDIR/install/pihole_scripts/vars /home/$USER/piprse/pihole_vpn/.env
}

# Configuring environmental variables for pihole container
vars_pihole_vpn() {
copy_env_file
get_timezone

# Asking about timezone if ok -> write timezone into .env file
whiptail --yesno "Your timezone is to: $TZ Do you want to proceed?" 20 60 2
  if [ $? -eq 0 ]; then
    sed -i 's+TIMEZONE_SED+'$TZ'+g' /home/$USER/piprse/pihole_vpn/.env
else
  return 0
fi

LAN_IP=$(whiptail --inputbox "Enter your raspberry pi's LAN IP: " 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+LAN_IP_SED+'$LAN_IP'+g' /home/$USER/piprse/pihole_vpn/.env
else
    return 0
fi

DOMAIN_NAME=$(whiptail --inputbox " \
  Enter your domain name: 
  (if you don't have your domain, enter domain 
   you like [only while installing without wireguard!])" 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+DOMAIN_NAME_SED+'$DOMAIN_NAME'+g' /home/$USER/piprse/pihole_vpn/.env
    sed -i 's+DOMAIN_NAME_SED+'$DOMAIN_NAME'+g' /home/$USER/piprse/pihole_vpn/scripts/external.conf
else
    return 0
fi

PIHOLE_PASS=$(whiptail --passwordbox "Enter password to pihole admin page: " 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+PIHOLE_PASS_SED+'$PIHOLE_PASS'+g' /home/$USER/piprse/pihole_vpn/.env
else
    return 0
fi
}

# Configuring environmental variables for wireguard
vars_wireguard() {
CLIENTS_NUMBER=$(whiptail --inputbox "How many VPN clients you want to create?" 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+CLIENTS_NUMBER_SED+'$CLIENTS_NUMBER'+g' /home/$USER/piprse/pihole_vpn/.env
else
    return 0
fi
}

# Configuring environmental variables for ddns
vars_ddns() {
DOMLOGIN=$(whiptail --inputbox "Enter login to dnsomatic.com" 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+dnsomaticlogin+'$DOMLOGIN'+g' /home/$USER/piprse/network/ddns/ddclient.conf
else
    return 0
fi

DOMPASS=$(whiptail --inputbox "Enter password to dnsomatic.com" 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+dnsomaticpass+'$DOMPASS'+g' /home/$USER/piprse/network/ddns/ddclient.conf
else
    return 0
fi
}

# Configuring environmental variables for nginx
vars_nginx() {
DNAME=$(whiptail --inputbox "\
  Enter your domain name:
  
  If you don't have domain enter whatever 
  domain you like.

  [First visit must be with http:// prefix]
  " 20 60 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
    sed -i 's+domainname+'$DNAME'+g' /home/$USER/piprse/network/nginx/nginx.conf
    sed -i 's+domainnamesed+'$DNAME'+g' /home/$USER/piprse/network/pidns.sh
else
    return 0
fi
}

# =============================================================================================================
# WIREGUARD CLIENTS CONFIG
# =============================================================================================================
menu_wireguard() {
  MENU=$(whiptail --title "Wireguard Configuration Menu" --menu "Wireguard configuration menu" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "1 Clients number" "Change the number of wireguard clients" \
    "2 QR codes" "Show the QR codes to connect devices" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$MENU" in
      1\ *) config_wireguard_clients ;;
      2\ *) config_wireguard_show_info ;;
      *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
    esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
  else
    return 0
  fi
}

# Configuration of wireguard clients number
config_wireguard_clients() {
  CLIENTS_NUMBER=$(whiptail --inputbox "How many VPN clients you want to have?" 20 60 3>&1 1>&2 2>&3)
  exitstatus=$?
  if [ $exitstatus = 0 ]; then
      # sed -i 's+CLIENTS_NUMBER_SED+'$CLIENTS_NUMBER'+g' /home/$USER/piprse/pihole_vpn/.env
      sed -i 's/\(CLIENTS_NUMBER=\)\(.*\)/\1'$CLIENTS_NUMBER'/' /home/$USER/piprse/pihole_vpn/.env
      docker-compose --env-file=/home/$USER/piprse/pihole_vpn/.env -f /home/$USER/piprse/pihole_vpn/docker-compose.yml up -d --build wireguard
      docker restart wireguard
  else
      return 0
  fi
}

# Print the wireguard connections info
config_wireguard_show_info() {
  i=1
  clients=$(sudo cat /home/$USER/piprse/pihole_vpn/.env | grep -oP '(?<=CLIENTS_NUMBER=).*')
  while [ $i -le $clients ]
  do
    echo 'Client '$i':'
    echo 'Configuration:'
    cat /home/$USER/piprse/pihole_vpn/wireguard/peer$i/peer$i.conf
    echo 'QR Code:'
    qrencode -t ansiutf8 < /home/$USER/piprse/pihole_vpn/wireguard/peer$i/peer$i.conf
    i=$(( i + 1 ))
  done
  read -r -p "Press any key to continue..." key
  return 0
}

# =============================================================================================================
# SETUP MENU
# =============================================================================================================
menu_setup() {
  MENU=$(whiptail --title "Setup Menu" --menu "Setup Menu" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "1 Initial setup" "Docker & Docker-Compose setup" \
    "2 Stack - Pihole_VPN" "Pihole, Unbound DNS, Wireguard setup" \
    "3 Stack - Network" "DDNS, Reverse Proxy setup" \
    "4 Stack - Management" "Portainer, Watchtower setup" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$MENU" in
      1\ *) setup_initial ;;
      2\ *) menu_pihole_vpn ;;
      3\ *) menu_network ;;
      4\ *) menu_management ;;
      *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
    esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
  else
    return 0
  fi
}

# =============================================================================================================
# SECURITY MENU
# =============================================================================================================
menu_sec() {
  MENU=$(whiptail --title "Security options" --menu "Security menu" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "1 SSH port" "Change the port of the SSH" \
    "2 SSH tarpit" "Setup the SSH Tarpit [port 22]" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$MENU" in
      1\ *) config_ssh ;;
      2\ *) check_ssh ;;
      *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
    esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
  else
    return 0
  fi
}

# =============================================================================================================
# CONFIG MENU
# =============================================================================================================
menu_config() {
  MENU=$(whiptail --title "Configuration" --menu "Configuration menu" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "1 System update" "Update & upgrade the system" \
    "2 Clean logs" "Clean logs of the specified container" \
    "3 Wireguard config" "Configure wireguard clients and show QR codes" \
    "4 Pihole update" "Update the pihole container" \
    "5 Power consumption" "Change options to save some power" \
    "6 Docker system prune" "Remove docker's unused stuff" \
    "7 Alias" "Set an 'piprse' alias to this tool" \
    "8 Timezone" "Change the timezone for this device" \
    "9 Remove" "Stop & delete all containers and clear docker data" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$MENU" in
      1\ *) update_system ;;
      2\ *) cleaning_dlogs ;;
      3\ *) menu_wireguard ;;
      4\ *) update_pihole ;;
      5\ *) menu_powersave ;;
      6\ *) docker_prune ;;
      7\ *) menu_alias ;;
      8\ *) config_timezone ;;
      9\ *) uninstall ;;
      *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
    esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
  else
    return 0
  fi
}

# =============================================================================================================
# ALIAS MENU
# =============================================================================================================
menu_alias() {
  ADIR=${SDIR}/piprse.sh
  if (whiptail --title "Alias option" --yesno "\
  Do you want to run this tool by typing 'piprse' anywhere in terminal?
  
  Select Yes to add an alias.
  
  Select No to remove an alias.

  !!! Alias will be available after next ssh login !!!
    $()\
    " 20 60 2); then
    echo "alias piprse='sudo bash $ADIR'" >> /home/$USER/.bashrc
    whiptail --msgbox "Alias has been added" 20 60
    return 0
  else
    grep -v "alias piprse='sudo bash $ADIR'" /home/$USER/.bashrc > /home/$USER/bashrc_tmpfile && mv /home/$USER/bashrc_tmpfile /home/$USER/.bashrc
    whiptail --msgbox "Alias has been removed" 20 60
    return 0
  fi
}

# =============================================================================================================
# MAIN MENU
# =============================================================================================================
size_window
while [ "$USER" = "root" ] || [ -z "$USER" ]; do
  if ! USER=$(whiptail --inputbox "Could not define the default user.\\n\\nPlease enter your user name:" 20 60 pi 3>&1 1>&2 2>&3); then
    return 0
  fi
done
while true; do
  MENU=$(whiptail --title "Pi Private Server" --menu "Main menu" $W_HEIGHT $W_WIDTH $W_MENU_HEIGHT --cancel-button Finish --ok-button Select \
    "1 Setup menu" "Menu with installation options" \
    "2 Configuration" "Configure some additional options" \
    "3 Security" "Security options" \
    "4 Instruction" "Some basic information" \
    "5 About" "About this tool" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    clear
    exit 0
  elif [ $RET -eq 0 ]; then
    case "$MENU" in
      1\ *) menu_setup ;;
      2\ *) menu_config ;;
      3\ *) menu_sec ;;
      4\ *) instruction ;;
      5\ *) about ;;
      *) whiptail --msgbox "Error: bad option selected" 20 60 1 ;;
    esac || whiptail --msgbox "Error while handling $MENU" 20 60 1
  else
    clear
    exit 1
  fi
done
