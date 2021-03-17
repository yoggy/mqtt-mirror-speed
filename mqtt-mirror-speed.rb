#!/usr/bin/ruby
require 'mqtt'
require 'logger'
require 'yaml'
require 'ostruct'
require 'json'
require 'date'

def usage
  puts "usage : #{$0} config.yaml"
  exit 1
end

system("sudo ifconfig enx106f3f66792e promisc")

$stdout.sync = true
Dir.chdir(File.dirname($0))
$current_dir = Dir.pwd

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

usage if ARGV.size == 0

$conf = OpenStruct.new(YAML.load_file(ARGV[0]))

$rx_bytes_path = "/sys/class/net/#{$conf.watch_interface}/statistics/rx_bytes"
$rx_packets_path = "/sys/class/net/#{$conf.watch_interface}/statistics/rx_packets"
if !File.exist?($rx_bytes_path)
  $logger.error("invalid watch_interface...watch_interface=#{$conf.watch_interface}"); 
  exit 1
end

$conn_opts = {
  remote_host: $conf.mqtt_host,
  client_id: $conf.mqtt_client_id
}

if !$conf.mqtt_port.nil?
  $conn_opts["remote_port"] = $conf.mqtt_port
end

if $conf.mqtt_use_auth == true
  $conn_opts["username"] = $conf.mqtt_username
  $conn_opts["password"] = $conf.mqtt_password
end


def read_rx_bytes()
  n = 0
  open($rx_bytes_path) do |f|
    n = f.read.to_i
  end
  n
end

def read_rx_packets()
  n = 0
  open($rx_packets_path) do |f|
    n = f.read.to_i
  end
  n
end

$past_rx_bytes = read_rx_bytes()
$past_rx_packets = read_rx_packets()

$log.info "connecting..."
MQTT::Client.connect($conn_opts) do |c|
  $log.info "connected!"
  loop do
    sleep $conf.watch_interval

    now_rx_bytes = read_rx_bytes
    diff_rx_bytes = now_rx_bytes - $past_rx_bytes
    $past_rx_bytes = now_rx_bytes
    next if diff_rx_bytes < 0

    now_rx_packets = read_rx_packets
    diff_rx_packets = now_rx_packets - $past_rx_packets
    $past_rx_packets = now_rx_packets
    next if diff_rx_packets < 0

    bit_per_sec = diff_rx_bytes * 8
    h = {}
    h["bps"] = bit_per_sec
    h["rx_packets"] = diff_rx_packets
    h["watch_interval"] = $conf.watch_interval
    h["last_update_time"] = DateTime.now.iso8601(0)
    json_str = h.to_json

    $log.info "publish: topic=#{$conf.publish_topic}, message=#{json_str}"
    c.publish($conf.publish_topic, json_str, true)
  end 
end
