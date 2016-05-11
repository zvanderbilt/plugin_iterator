require "plugin_iterator/version"

module PluginIterator

	require 'optparse'
	require 'pp'
	require 'find'
	require 'mysql'
	require 'wpcli'
	require 'csv'
	require 'mail'

	class WPParser

	def self.parse(args)
		# The options specified on the command line will be collected in *options*.
		# We set default values here.
		options = {
			name: 'wp_plugins',
			dest: '/tmp/',
			target: './',
			to: 'root'
			}

		opts = OptionParser.new do |opts|
			opts.banner = "Usage: #$0 [options]"
			opts.separator ""
			opts.separator "Specific options:"

		  # Cast 'target dir' argument to a  object.
			opts.on("-t", "--target TARGET", "Path to begin searching from") do |target| 
				options[:target] = target
			end

		  # Cast 'dest' argument to a  object.
			opts.on("-d", "--dest [DESTINATION]", "CSV Destination") do |dest|
				options[:dest] = dest
			end

		  # Cast 'name' argument to a  object.
			opts.on("-n", "--name [NAME]", "CSV name") do |name|
				options[:name] = name
			end
		
		# Cast 'To Address' argument to a  object.
			opts.on("-m", "--mailto [MAILTO]", "Email Recipient") do |to|
				options[:to] = to
			end

			# Boolean switch.
			opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
				options[:verbose] = v
			end

			opts.separator ""
			opts.separator "Common options:"

			# No argument, shows at tail.  This will print an options summary.
			opts.on_tail("-h", "--help", "Show this message") do
				puts opts
				exit
			end

			opts.on_tail("-V", "--version", "Show version") do
				puts Version
				exit
			end
		end
		
		opts.parse!
		options

	end  # parse
	end  # class OptionParser

	class Iterator

	def initialize(options)
		@options = options 
		@target = @options[:target]
		generate_csv(options)
		@target_csv = Dir.glob("#{@options[:dest]}#{@options[:name]}*\.csv").max_by {|f| File.mtime(f)}
	end


	def wp_found(options)
		begin
		puts "Hello, #{@options[:target]} shall be searched to find WP installations..."
		puts @target_csv
		wpconfigs = Array.new()
		Find.find(@options[:target]) do |path|
			wpconfigs << Dir.glob(path).grep_v(/(bak|Bak|repo|archive|Backup|html(\-|\.))/)	
		end

		wpconfigs.each do |file|
			@wpcli = Wpcli::Client.new File.dirname(file)
			puts "Getting plugins for..."

			name, user, password, host = File.read(file).scan(/'DB_[NAME|USER|PASSWORD|HOST]+'\, '(.*?)'/).flatten
			@site_name = get_site_name(name, user, password, host)
			puts @site_name
	#	    site_name = @wpcli.run "option get siteurl --allow-root"
	#		puts site_name
			CSV.open(@target_csv, "a") do |csv|
				csv << ["#{@site_name}",] 
			end

			plugins = @wpcli.run "plugin list --allow-root"
			plugins.each do |plugin|
				puts "#{plugin[:name]} is version #{plugin[:version]} and an update is #{plugin[:update]}"
				CSV.open(@target_csv, "a") do |csv|
					csv << ['', plugin[:name], plugin[:version], plugin[:update]]
				end
			end
		end
		send_mail(@options)
		rescue => e
			puts e
		end
	end

	def get_site_name(db_name, db_user, db_pass, db_host)
		begin
		con = Mysql.new("#{db_host}", "#{db_user}", "#{db_pass}", "#{db_name}")
		rs = con.query('SELECT option_value FROM wp_options WHERE option_id = 1')
		return rs.fetch_row[0]

		rescue => e
			puts e
		end
	ensure
		con.close if con
	end

	def generate_csv(options)
		begin
		CSV.open("#{@options[:dest]}/#{@options[:name]}-#{Time.now}.csv", "a+") do |csv|
			csv << ["Site name", "Plugin", "Version", "Upgradeable"]
		end
		rescue => e
			puts e
		end
	end
	def send_mail(options)
		begin
			Mail.deliver do
				from      "ruby_slave@localhost"
				to        "#@options[:to]}"
				subject   "Plugin Update Status"
				body      "See attachment for details"
				add_file  Dir.glob(@target_csv)
			end
		rescue => e
			puts e
		end
	end

	end # class Iterator


	### EXECUTE ###
	begin
		options = WPParser.parse(ARGV)
		options
	 
		Iterator.new(options).wp_found(options)

	rescue => e
		puts e
	end
end
