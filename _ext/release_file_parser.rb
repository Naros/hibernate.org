require 'nokogiri'
require 'open-uri'
require 'uri'

module Awestruct
  module Extensions
    # Awestrcut extension which traverses the given directory to find release files, specifyig
    # the relevant release information for a given release and project. Directories are used to 
    # create sub-hashes.
    class ReleaseFileParser

      def initialize(data_dir="_data")
        @data_dir = data_dir
      end

      def watch(watched_dirs)
          watched_dirs << @data_dir
      end

      def execute(site)
        # first create the nested hashes for the release data
        createReleaseData( "#{site.dir}/#{@data_dir}", site, site )

        # also create a sorted array for the releases
        createSortedReleaseHash( site )
      end

      private
      def createReleaseData(dir, hash, site)
        Dir[ "#{dir}/*" ].each do |entry|
          if ( File.directory?( entry ) )
            subHash = createSubHashForKey(hash, File.basename( entry ))
            createReleaseData( entry, subHash, site )
          else
            createHashForRelease( hash, entry, site )
          end
        end
      end

      # Creates a sub hash with the specified key in case it does not exist yet
      def createSubHashForKey(hash, key)
        if ( hash[key].nil? )
          hash[key] = Hash.new
        end
        hash[key]
      end

      # Creates a hash with the date read from a release file
      def createHashForRelease(hash, file, site)
          # load the release data 
          releaseHash = site.engine.load_page( file )
          # use a regexp to get the file name without extension into the pattern buffer.
          # file name == version
          File.basename( file ) =~ /^(.*)\.\w*$/
          # use the file (release) name as key
          key = $1.to_s
          hash[ key ] = releaseHash
      end

      def createSortedReleaseHash(site)
        site.projects.each do |projectname, project|
          releases = project[:releases]
          unless releases.nil?
            sortedReleases = Hash[releases.sort_by { |key, value| Version.new(key) }.reverse]
            site.projects[projectname][:sorted_releases] = sortedReleases.values
          end
        end
      end
    end

    # Custom version class able to understand and compate the project versions of Hibernate projects
    class Version
      include Comparable

      attr_reader :major, :feature_group, :feature, :bugfix

      def initialize(version="")
        v = version.to_s.split(".")
        @major = v[0].to_i
        @feature_group = v[1].to_i
        @feature = v[2].to_i
        @bugfix = v[3].to_s
      end
      
      def <=>(other)
        return @major <=> other.major if ((@major <=> other.major) != 0)
        return @feature_group <=> other.feature_group if ((@feature_group <=> other.feature_group) != 0)
        return @feature <=> other.feature if ((@feature <=> other.feature) != 0)
        return @bugfix <=> other.bugfix
      end

      def self.sort
        self.sort!{|a,b| a <=> b}
      end

      def to_s
        @major.to_s + "." + @feature_group.to_s + "." + @feature.to_s + "." + @bugfix.to_s
      end
    end

    # Helper class to retrieve the dependencies of a release by parsing the release POM
    class ReleaseDependencies
      Nexus_base_url = 'https://repository.jboss.org/nexus/content/repositories/public/org/hibernate/'

      def initialize(artifact, version)
        # init instance variables
        @properties = Hash.new
        @dependencies = Hash.new

        # try loading the pom
        uri = get_uri(artifact, version)
        doc = create_doc(uri)
        if has_parent(doc) 
          # parent pom needs to be loaded first
          parent_uri = get_uri(doc.xpath('//parent/artifactId').text, doc.xpath('//parent/version').text)
          parent_doc = create_doc(parent_uri)
          process_doc(parent_doc)
        end
        process_doc(doc)
      end 

      def get_value(property)
        @properties[property]
      end

      def get_version(group_id, artifact_id)
        @dependencies[group_id + ':' + artifact_id]
      end

      private
      def create_doc(uri)
        begin
          doc = Nokogiri::XML(open(uri))
        rescue OpenURI::HTTPError => error
          raise "Unable to access uri #{uri}. Reason: #{error}"
        end
        doc.remove_namespaces!
      end

      def process_doc(doc)
        load_properties(doc)
        extract_dependencies(doc)
      end

      def get_uri(artifact, version)
        Nexus_base_url + artifact + '/' + version + '/' + artifact + '-' + version + '.pom'
      end

      def has_parent(doc)
        !doc.xpath('//parent').empty?
      end

      def load_properties(doc)
          doc.xpath('//properties/*') .each do |property|
          key = property.name
          value = property.text
          @properties[key] = value
        end
      end

      def extract_dependencies(doc)
        doc.xpath('//dependency') .each do |dependency|
          group_id = dependency.xpath('./groupId').text
          artifact_id = dependency.xpath('./artifactId').text
          version = dependency.xpath('./version').text
          if ( version =~ /\$\{(.*)\}/ )
            version = @properties[$1]
          end
          key = group_id + ':' + artifact_id
          if @dependencies[key] == nil
            @dependencies[key] = version
          end
        end
      end
    end
  end
end
