class NetworkHandler
  class Bridge
    def initialize(network)
      @network = network
      if !network.namespace || !network.container_ip
        raise ArgumentError, "Required network config(s) are missing: #{network.inspect}"
      end
    end
    attr_reader :network

    def to_ns_file
      "/var/run/netns/#{network.namespace}"
    end
    alias ns_file to_ns_file

    def generate
      make_network_namespace
      make_veth
      make_container_network
    end

    def cleanup
      return unless File.exist?(ns_file)

      unless system("ip netns del #{network.namespace}")
        raise "Cleanup of namespace failed"
      end
      system "ip link del #{network.veth_host} || true"
    end

    private
    def make_network_namespace
      unless system("ip netns add #{network.namespace}")
        raise "Creating namespace failed"
      end
    end

    def make_veth
      [
        "ip link add #{network.veth_host} type veth peer name #{network.veth_guest}",
        "ip link set #{network.veth_host} up",
        "ip link set dev #{network.veth_host} master #{network.bridge_name}"
      ].each do |cmd|
        unless system(cmd)
          raise "Creating veth failed: #{cmd}"
        end
      end
    end

    def make_container_network
      ns = network.namespace
      [
        "ip link set #{network.veth_guest} netns #{ns} up",
        "ip netns exec #{ns} ip addr add #{network.container_ip}/#{network.netmask} dev #{network.veth_guest}",
        "ip netns exec #{ns} ip link set lo up",
        "ip netns exec #{ns} ip route add default via #{network.bridge_ip}"
      ].each do |cmd|
        unless system(cmd)
          raise "Creating container networks failed: #{cmd}"
        end
      end
    end

    def self.generate_bridge(bridge_name, bridge_ip_netmask)
      unless bridge_ip_netmask =~ /\/\d+$/
        bridge_ip_netmask << '/24'
      end
      runner = RunCmd.new("init.network.bridge")
      [
        "ip link add #{bridge_name} type bridge",
        "ip addr add #{bridge_ip_netmask} dev #{bridge_name}",
        "ip link set dev #{bridge_name} up"
      ].each do |cmd|
        _, status = runner.run(cmd)
        if !status.success?
          raise "Creating container networks failed: #{cmd}"
        end
      end
    end
  end
end
