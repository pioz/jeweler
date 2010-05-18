require 'rake'
require 'rake/tasklib'

class Jeweler
  # Rake tasks for build a Debian package (.deb).
  #
  # This tasks create a _meta_ debian package that means that when you
  # install it the installation process call <tt>gem install</tt> to
  # install the gem and the remove process call <tt>gem uninstall</tt>
  # to remove the gem. Also, if the gem have binaries, bash scripts
  # will be created to run the gem's binaries.
  #
  # Jeweler::Tasks.new needs to be used before this.
  #
  # Basic usage:
  #
  #     Jeweler::DebTasks.new
  #
  # Easy enough, right?
  # 
  # There are some options you can tweak, you can pass DEBIAN/control fields
  #
  # * *package* (mandatory). The name of the binary package.
  # * *source*.
  # * *version* (mandatory). The version number of a package. The format is: [epoch:]upstream_version[-debian_revision].
  # * *section* (recommended). This field specifies an application area into which the package has been classified. See section 2.4 of Debian Policy doc.
  # * *priority* (recommended). This field represents how important it is that the user have the package installed. See section 2.5 of Debian Policy doc.
  # * *architecture* (mandatory). Depending on context and the control file used, the Architecture field can include the following sets of values:
  #   * A unique single word identifying a Debian machine architecture as described in Architecture specification strings, section 11.1 of Debian Policy doc.
  #   * <tt>all</tt>, which indicates an architecture-independent package.
  #   * <tt>any</tt>, which indicates a package available for building on any architecture.
  #   * <tt>source</tt>, which indicates a source package.
  # * *essential*. This is a boolean field which may occur only in the control file of a binary package or in a per-package fields paragraph of a main source control data file.
  # * *depends*. Packages can declare in their control file that they have certain relationships to other packages - for example, that they may not be installed at the same time as certain other packages, and/or that they depend on the presence of others. See Debian Policy doc.
  # * *installed_size*. This field appears in the control files of binary packages, and in the Packages files. It gives an estimate of the total amount of disk space required to install the named package. Actual installed size may vary based on block size, file system properties, or actions taken by package maintainer scripts.
  # * *maintainer* (mandatory). The package maintainer's name and email address. The name should come first, then the email address inside angle brackets <> (in RFC822 format).
  # * *description* (mandatory). In a source or binary control file, the Description field contains a description of the binary package, consisting of two parts, the synopsis or the short description, and the long description. The field's format is as follows:
  #
  #    Description: <single line synopsis>
  #     <extended description over several lines>
  #
  # * *homepage*. The URL of the web site for this package, preferably (when applicable) the site from which the original source can be obtained and any additional upstream documentation or information may be found. The content of this field is a simple URL without any surrounding characters such as <>.
  #
  # For complete info of DEBIAN/control file see the Debian Policy (http://www.debian.org/doc/debian-policy/ch-controlfields.html).
  #
  # If you do not pass options, like this
  #
  #    Jeweler::DebTasks.new do |control|
  #      control.package = 'Jeweler'
  #      control.depends = 'ruby (>= 1.8.7), rubygems (>= 1.3.5)'
  #    end
  #
  # some fields will be filled with gemspec options:
  #
  #    package = jeweler.gemspec.name
  #    version = jeweler.version
  #    maintainer = jeweler.gemspec.authors.first
  #    architecture = 'all'
  #    homepage = jeweler.gemspec.homepage
  #    description = jeweler.gemspec.summary
  #
  # See also http://wiki.github.com/technicalpickles/jeweler/rubyforge
  class DebTasks < ::Rake::TaskLib
    attr_accessor :jeweler

    # Fields of <tt>DEBIAN/control</tt> file for binary package.
    @@control_fields = [ :package, :source, :version, :section, :priority,
                         :architecture, :essential, :depends, :installed_size,
                         :maintainer, :homepage, :description, :description_extended ]
    attr_accessor *@@control_fields

    def initialize
      # Set some control fields like gemspec fields
      @package = jeweler.gemspec.name
      @version = jeweler.version
      @architecture = 'all'
      @maintainer = jeweler.gemspec.authors.first
      unless @maintainer.nil? || jeweler.gemspec.email.nil?
        @maintainer += " <#{jeweler.gemspec.email}>"
      end
      @homepage = jeweler.gemspec.homepage
      @description = jeweler.gemspec.summary
      @description_extended = jeweler.gemspec.description

      yield self if block_given?

      # Always add ruby and rubygems depends
      if @depends.nil?
        @depends = 'ruby (>= 1.8.7), rubygems (>= 1.3.5)'
      else
        unless @depends.match(/(, *|^)rubygems *(,|\(|\[|$)/)
          @depends = 'rubygems (>= 1.3.5), ' + @depends
        end
        unless @depends.match(/(, *|^)ruby *(,|\(|\[|$)/)
          @depends = 'ruby (>= 1.8.7), ' + @depends
        end
      end
      # Get bin files
      @bin_files = Dir['bin/*'].collect {|path| File.basename(path) }
      # Define tasks
      define
    end

    def jeweler
      @jeweler ||= Rake.application.jeweler
    end

    # Setup the debian/control
    def setup_control_file
      error = 'Packege field for control file is mandatory'      if @package.nil?
      error = 'Version field for control file is mandatory'      if @version.nil? 
      error = 'Architecture field for control file is mandatory' if @architecture.nil?
      error = 'Maintainer field for control file is mandatory'   if @maintainer.nil?
      error = 'Description field for control file is mandatory'  if @description.nil?
      unless error.nil?
        puts "ERROR! #{error}."
        return false
      else        
        # Setup debian control file
        @control = ''
        (@@control_fields - [:description_extended]).each do |field|
          @control << "#{field.to_s.capitalize}: #{send(field)}\n" unless send(field).nil?
        end
        unless description_extended.nil?
          @control += " #{$DESCRIPTION.gsub(/(.{1,79})( +|$\n?)|(.{1,79})/, "\\1\\3\n ")[0..-3]}\n"
        end
        return true
      end
    end

    def define
      namespace :deb do

        desc 'Print debian/control file'
        task :control do
          if setup_control_file
            puts @control
          end
        end

        desc 'Create only the package structure inside ./deb/ directory'
        task :create_structure do
          if setup_control_file
            # Setup post installation script
            postinst  = "#!/usr/bin/ruby\n"
            postinst += "puts `gem install #{@package} -v #{@version} --no-rdoc --no-ri`"
            # Setup pre remove script
            prerm  = "#!/usr/bin/ruby\n"
            prerm += "puts `gem uninstall #{@package} -v #{@version} -ax`"
            # Create repository base directories
            Dir.mkdir('deb/') unless File.exists?('deb/')
            Dir.mkdir('deb/DEBIAN/') unless File.exists?('deb/DEBIAN/')
            # Setup scripts to launch the gem binaries
            @bin_files.each do |bin|
              unless File.exists?("/usr/bin/#{bin}")
script = <<-EOF
#!/usr/bin/ruby
require 'rubygems'
Gem.path.each do |path|
  bin_path = "\#{path}/bin/#{bin}"
  if File.exists?(bin_path)
    `\#{bin_path}`
    break
  end
end
EOF
                Dir.mkdir('deb/usr/') unless File.exists?('deb/usr/')
                Dir.mkdir('deb/usr/bin/') unless File.exists?('deb/usr/bin/')
                File.open("deb/usr/bin/#{bin}", 'w') {|f| f.write(script) }
                File.chmod(0755, "deb/usr/bin/#{bin}")
              end
            end
            # Write files
            File.open('deb/DEBIAN/control', 'w') {|f| f.write(@control) }
            File.open('deb/DEBIAN/postinst', 'w') {|f| f.write(postinst) }
            File.open('deb/DEBIAN/prerm', 'w') {|f| f.write(prerm) }
            File.chmod(0755, 'deb/DEBIAN/postinst', 'deb/DEBIAN/prerm')
            # Calculate md5sums file
            md5sums = ''
            Dir['deb/usr/**/*'].each do |f|
              unless File.directory?(f)
                md5sums << `md5sum #{f}`
              end
            end
            File.open('deb/DEBIAN/md5sums', 'w') {|f| f.write(md5sums) }
          end
        end

        desc 'Build debian package (.deb) from ./deb/ directory. If directory do not exists, create it'
        task :build do
          if File.exists?('/usr/bin/dpkg-deb')
            Rake::Task['deb:create_structure'].execute unless File.exists?('deb/')
            # Build package
            if File.exists?('deb/')
              puts `dpkg-deb -b deb/ '#{@package}_#{@version}_#{@architecture}.deb'`
            end
          else
            raise "'dpkg-deb' program not found. Can't create deb package."
          end
        end

        desc 'Remove ./deb/ directory'
        task :clean do
          if File.exists?('deb/')
            require 'fileutils'
            FileUtils.rm_rf('deb/')
          end
        end

      end
    end

  end
end
