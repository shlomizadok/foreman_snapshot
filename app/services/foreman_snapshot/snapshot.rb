module ForemanSnapshot
  class Snapshot
    include Foreman::Renderer

    attr_reader :host
    SUPPORTED_PROVIDERS = %w[Libvirt Openstack]
    PROVIDERS = SUPPORTED_PROVIDERS.reject { |p| !SETTINGS[p.downcase.to_sym] }

    delegate :compute_resource, :hostgroup, :compute_object, :image, :to => :host
    delegate :logger, :to => :Rails
    alias_method :vm, :compute_object

    def initialize(opts = {})
      @host = opts[:host]
      raise ::Foreman::Exception.new(N_("must provide a host for snapshot")) unless @host.present?
    end

    def self.new_snapshot(opts = {})
      PROVIDERS.each do |p|
        if p.downcase == opts[:host].compute_resource.provider_friendly_name.downcase
          return "ForemanSnapshot::Snapshot::#{p}".constantize.new(opts)
        end
      end
      raise ::Foreman::Exception.new N_("unknown snapshot provider")
    end

    # takes an existing Host, and convert it into an image based on his HG.
    def create
      template = template_file  # workaround to ensure tempfile sticks around a bit longer
      client = Foreman::Provision::SSH.new ip, username, { :template => template.path }.merge(credentials)

      # we have a puppet cert already, thanks to this being a built host
      # Just need to ensure the template has "puppet agent -tv" inside to get a full run
      if client.deploy!
        # Built the image, so snapshot it, and get the response from Fog
        name = "#{hostgroup.to_label} - #{DateTime.now.strftime("%m/%d/%Y")}"
        title = "Foreman Hostgroup #{hostgroup.to_label} Image"
        snapshot = compute_resource.snapshot_vm(host.uuid, title)
        raise "failed to snapshot #{snapshot}" unless snapshot
        wait_for_active(snapshot)
        # Create a new Image in Foreman that links to it
        Image.find_or_create_by_name(
          {
            :name                => name,
            :uuid                => snapshot,
            :hostgroup_id        => hostgroup.id,
            :compute_resource_id => compute_resource.id,
          }.merge(image_hash)
        )
      end
    ensure
      template.unlink if template
    end

    private

    def ip
      raise ::Foreman::Exception.new(N_("Not implemented for %s"), provider_friendly_name)
    end

    def credentials
      raise ::Foreman::Exception.new(N_("Not implemented for %s"), provider_friendly_name)
    end

    def username
      raise ::Foreman::Exception.new(N_("Not implemented for %s"), provider_friendly_name)
    end

    def image_hash
      raise ::Foreman::Exception.new(N_("Not implemented for %s"), provider_friendly_name)
    end

    def cleanup_template
      ConfigTemplate.find_by_name('Imagify').try(:template) || raise('unable to find template Imagify')
    end

    def template_file
      unattended_render_to_temp_file(cleanup_template, hostgroup.id.to_s)
    end

    def wait_for_active id
      # We can't delete the underlying Host until the image has finished saving
      until compute_resource.snapshot_status(id) == "ACTIVE"
        sleep 1
      end
    end

    def provider_friendly_name
      @host.compute_resource.provider_friendly_name
    end

  end
end
