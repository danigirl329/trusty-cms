require 'highline'
require 'forwardable'

module TrustyCms
  class Setup
    class << self
      def bootstrap(config)
        setup = new
        setup.bootstrap(config)
        setup
      end
    end

    attr_accessor :config

    def bootstrap(config)
      @config = config
      @admin = create_admin_user(config[:admin_name], config[:admin_username], config[:admin_password])
      load_default_configuration
      # load_database_template(config[:database_template])
      announce 'Finished.'
    end

    def create_admin_user(name, username, password)
      unless name && username && password
        announce 'Create the admin user (press enter for defaults).'
        name ||= prompt_for_admin_name
        username ||= prompt_for_admin_username
        password ||= prompt_for_admin_password
      end
      attributes = {
        name: name,
        login: username,
        password: password,
        password_confirmation: password,
      }
      admin = User.find_by(login: username)
      admin ||= User.new
      admin.update_attributes(attributes)
      admin.admin = true
      admin.save
      admin
    end

    def load_default_configuration
      feedback "\nInitializing configuration" do
        step { TrustyCms::Config['admin.title'] = 'TrustyCms CMS' }
        step { TrustyCms::Config['admin.subtitle'] = 'Publishing for Small Teams' }
        step { TrustyCms::Config['defaults.page.parts'] = 'body, extended' }
        step { TrustyCms::Config['defaults.page.status'] = 'Draft' }
        step { TrustyCms::Config['defaults.page.filter'] = nil }
        step { TrustyCms::Config['defaults.page.fields'] = 'Keywords, Description' }
        step { TrustyCms::Config['session_timeout'] = 2.weeks }
        step { TrustyCms::Config['default_locale'] = 'en' }
      end
    end

    def load_database_template(filename)
      template = nil
      if filename
        name = find_template_in_path(filename)
        if name
          template = load_template_file(name)
        else
          announce "Invalid template name: #{filename}"
          filename = nil
        end
      end
      unless filename
        templates = find_and_load_templates("#{TRUSTY_CMS_ROOT}/db/templates/*.yml")
        templates.concat find_and_load_templates("#{TRUSTY_CMS_ROOT}/vendor/extensions/**/db/templates/*.yml")
        TrustyCms::Extension.descendants.each do |d|
          templates.concat find_and_load_templates(d.root + '/db/templates/*.yml')
        end
        templates.concat find_and_load_templates("#{Rails.root}/vendor/extensions/**/db/templates/*.yml")
        templates.concat find_and_load_templates("#{Rails.root}/db/templates/*.yml")
        templates.uniq!
        choose do |menu|
          menu.header = "\nSelect a database template"
          menu.prompt = "[1-#{templates.size}]: "
          menu.select_by = :index
          templates.each { |t| menu.choice(t['name']) { template = t } }
        end
      end
      create_records(template)
    end

    private

    def prompt_for_admin_name
      username = ask('Name (Administrator): ', String) do |q|
        q.validate = /^.{0,100}$/
        q.responses[:not_valid] = 'Invalid name. Must be under 100 characters long.'
        q.whitespace = :strip
      end
      username = 'Administrator' if username.blank?
      username
    end

    def prompt_for_admin_username
      username = ask('Username (admin): ', String) do |q|
        q.validate = /^(|.{3,40})$/
        q.responses[:not_valid] = 'Invalid username. Must be at least 3 characters long.'
        q.whitespace = :strip
      end
      username = 'admin' if username.blank?
      username
    end

    def prompt_for_admin_password
      default_password = 'trusty'
      password = ask("Password (#{default_password}): ", String) do |q|
        q.echo = false unless defined?(::JRuby) # JRuby doesn't support stty interaction
        q.validate = /^(|.{5,40})$/
        q.responses[:not_valid] = 'Invalid password. Must be at least 5 characters long.'
        q.whitespace = :strip
      end
      password = default_password if password.blank?
      password
    end

    def find_template_in_path(filename)
      (
        [
          filename,
          "#{TRUSTY_CMS_ROOT}/#{filename}",
          "#{TRUSTY_CMS_ROOT}/db/templates/#{filename}",
          "#{Rails.root}/#{filename}",
          "#{Rails.root}/db/templates/#{filename}",
          "#{Dir.pwd}/#{filename}",
          "#{Dir.pwd}/db/templates/#{filename}",
        ] +
        Dir.glob("#{TRUSTY_CMS_ROOT}/vendor/extensions/**/db/templates/#{filename}") +
        Dir.glob("#{Rails.root}/vendor/extensions/**/db/templates/#{filename}") +
        TrustyCms::Extension.descendants.inject([]) do |r, d|
          r << "#{d.root}/db/templates/#{filename}"
        end
      ).find { |name| File.file?(name) }
    end

    def find_and_load_templates(glob)
      templates = Dir[glob]
      templates.map! { |template| load_template_file(template) }
      templates.sort_by { |template| template['name'] }
    end

    def load_template_file(filename)
      YAML.load_file(filename)
    end

    def create_records(template)
      records = template['records']
      if records
        puts
        records.keys.each do |key|
          feedback "Creating #{key.to_s.underscore.humanize}" do
            model = model(key)
            model.reset_column_information
            record_pairs = order_by_id(records[key])
            step do
              record_pairs.each do |_id, record|
                model.new(record).save
              end
            end
          end
        end
      end
    end

    def model(model_name)
      model_name.to_s.singularize.constantize
    end

    def order_by_id(records)
      records.map { |_name, record| [record['id'], record] }.sort { |a, b| a[0] <=> b[0] }
    end

    extend Forwardable
    def_delegators :terminal, :agree, :ask, :choose, :say

    def terminal
      @terminal ||= HighLine.new
    end

    def output
      terminal.instance_variable_get('@output')
    end

    def wrap(string)
      string = terminal.send(:wrap, string) unless terminal.wrap_at.nil?
      string
    end

    def print(string)
      output.print(wrap(string))
      output.flush
    end

    def puts(string = "\n")
      say string
    end

    def announce(string)
      puts "\n#{string}"
    end

    def feedback(process)
      print "#{process}..."
      if yield
        puts 'OK'
        true
      else
        puts 'FAILED'
        false
      end
    rescue Exception => e
      puts 'FAILED'
      raise e
    end

    def step
      yield if block_given?
      print '.'
    end
  end
end
