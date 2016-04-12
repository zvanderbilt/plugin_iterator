#!/usr/bin/env ruby

require 'optparse'
require 'pp'
require 'find'
require 'mysql'
require 'wpcli'
require 'csv'
require 'mail'

class WPParser

Version = 1.1

def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = {
        name: 'wp_installs.csv',
        dest: './',
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

def wp_found(options)
    begin
    @options = options
    
    puts "Hello, #{@options[:target]} shall be searched to find WP installations..."
    
    wpconfigs = Array.new()
        Find.find(@options[:target]) do |path|
        wpconfigs << path if path =~ /\/html\/wp\-config\.php$/
    end

    wpconfigs.each do |file|
        if file =~ /bak/
            next	
        end
        name, user, password, host = File.read(file).scan(/'DB_[NAME|USER|PASSWORD|HOST]+'\, '(.*?)'/).flatten
        puts "Getting plugins for..."
        @site_name = get_site_name(name, user, password, host)
	    puts @site_name

        target_csv = Dir.glob("/tmp/plugins_*").max_by {|f| File.mtime(f)}

        @wpcli = Wpcli::Client.new File.dirname(file)

        CSV.open(target_csv, "a") do |csv|
            csv << [@site_name,]
        end

        plugins = @wpcli.run "plugin list --allow-root"
        plugins.each do |plugin|
            puts "#{plugin[:name]} is version #{plugin[:version]} and an update is #{plugin[:update]}"
            CSV.open(target_csv, "a") do |csv|
                csv << ['', plugin[:name], plugin[:version], plugin[:update]]
            end
        end
    end
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

def generate_csv()
    begin
    CSV.open("/tmp/plugins_#{Time.now}.csv", "a+") do |csv|
        csv << ["Site name", "Plugin", "Version", "Upgradeable"]
    end
    rescue => e
        puts e
    end
end
def send_mail(options)
@options = options
    begin
        Mail.deliver do
            from      "ruby_slave@kiosk.tm"
            to        "#{options[:to]}"
            subject   "Plugin Update Status"
            body      File.read(Dir.glob("/tmp/plugins_*").max_by {|f| File.mtime(f)})
            add_file  Dir.glob("/tmp/plugins_*").max_by {|f| File.mtime(f)}
        end
    rescue => e
        puts e
    end
end

begin
    options = WPParser.parse(ARGV)
    options


# Generate CSV with header row
    generate_csv()
# Print db connection info and site name
    puts wp_found(options)
# Send notification email with csv attachment
    send_mail(options)

rescue => e
    puts e
end
