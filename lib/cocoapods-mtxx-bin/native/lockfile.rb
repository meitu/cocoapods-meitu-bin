module Pod
  class Lockfile
    def detect_changes_with_podfile(podfile)
      result = {}
      [:added, :changed, :removed, :unchanged].each { |k| result[k] = [] }

      installed_deps = {}
      dependencies.each do |dep|
        name = dep.root_name
        installed_deps[name] ||= dependencies_to_lock_pod_named(name)
      end

      installed_deps = installed_deps.values.flatten(1).group_by(&:name)

      podfile_dependencies = podfile.dependencies
      podfile_dependencies_by_name = podfile_dependencies.group_by(&:name)

      all_dep_names = (dependencies + podfile_dependencies).map(&:name).uniq
      all_dep_names.each do |name|
        installed_dep   = installed_deps[name]
        installed_dep &&= installed_dep.first

        # 需要将二进制版本的 specific_version 最后一位去掉，否则二进制下依赖解析很慢
        unless installed_dep.nil?
          installed_dep_version = installed_dep.specific_version.to_s
          if installed_dep_version.include?('bin')
            req_arr = installed_dep_version.split('.').delete_if { |r| r.include?('bin') }
            installed_dep_version = req_arr.join('.')
            installed_dep.specific_version = Pod::Version.create(installed_dep_version)
          end
        end

        podfile_dep     = podfile_dependencies_by_name[name]
        podfile_dep   &&= podfile_dep.first

        if installed_dep.nil?  then key = :added
        elsif podfile_dep.nil? then key = :removed
        elsif podfile_dep.compatible?(installed_dep) then key = :unchanged
        else key = :changed
        end
        result[key] << name
      end
      result
    end

    class << self
      def generate(podfile, specs, checkout_options, spec_repos = {})
        hash = {
          'PODS'             => generate_pods_data(specs),
          'DEPENDENCIES'     => generate_dependencies_data(podfile),
          'SPEC REPOS'       => generate_spec_repos(spec_repos),
          'EXTERNAL SOURCES' => generate_external_sources_data(podfile),
          'CHECKOUT OPTIONS' => checkout_options,
          'SPEC CHECKSUMS'   => generate_checksums(specs),
          'PODFILE CHECKSUM' => podfile.checksum,
          'USE BINARY'       => "#{podfile.use_binaries?}",
          'CONFIGURATION'    => ENV['configuration'] || podfile.configuration,
          'COCOAPODS'        => CORE_VERSION,
        }
        Lockfile.new(hash)
      end

      def generate_spec_repos(spec_repos)
        result = Hash.new
        spec_repos.map do |source, specs|
          next unless source
          next if specs.empty?
          key = source.url || source.name

          # save `trunk` as 'trunk' so that the URL itself can be changed without lockfile churn
          key = Pod::TrunkSource::TRUNK_REPO_NAME if source.name == Pod::TrunkSource::TRUNK_REPO_NAME

          value = specs.map { |s| s.root.name }.uniq
          # 合并重复的source源，而不是替换
          if result[key].nil?
            result[key] = YAMLHelper.sorted_array(value)
          else
            result[key] = YAMLHelper.sorted_array(result[key].concat(value))
          end
        end
        result.compact
      end
    end
  end
end
