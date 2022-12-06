

require 'parallel'
require 'cocoapods'
require 'cocoapods-meitu-bin/native/podfile'
require 'cocoapods-meitu-bin/native/sources_manager'
require 'cocoapods-meitu-bin/native/installation_options'
require 'cocoapods-meitu-bin/gem_version'
# require 'cocoapods-meitu-bin/command/bin/archive'
require 'cocoapods-meitu-bin/helpers/buildAll/bin_helper'
require 'cocoapods-meitu-bin/config/config'

module Pod
  class Resolver
    if Pod.match_version?('~> 1.6')
      # 其实不用到 resolver_specs_by_target 再改 spec
      # 在这个方法里面，通过修改 dependency 的 source 应该也可以
      # 就是有一点，如果改了之后，对应的 source 没有符合 dependency 的版本
      # 分析依赖阶段就会报错了，没法像 resolver_specs_by_target 一样
      # 没有对应的二进制版本时还可以转到源码源码
      #
      def aggregate_for_dependency(dependency)
        sources_manager = Config.instance.sources_manager
        if dependency&.podspec_repo
          sources_manager.aggregate_for_dependency(dependency)
          # 采用 lock 中的 source ，会导致插件对 source 的先后调整失效
          # elsif (locked_vertex = @locked_dependencies.vertex_named(dependency.name)) && (locked_dependency = locked_vertex.payload) && locked_dependency.podspec_repo
          #   sources_manager.aggregate_for_dependency(locked_dependency)
        else
          @aggregate ||= Source::Aggregate.new(sources)
        end
      end
    end

    if Pod.match_version?('~> 1.4')
      def specifications_for_dependency(dependency, additional_requirements_frozen = [])
        additional_requirements = additional_requirements_frozen.dup.compact
        requirement = Requirement.new(dependency.requirement.as_list + additional_requirements.flat_map(&:as_list))
        if podfile.allow_prerelease? && !requirement.prerelease?
          requirement = Requirement.new(dependency.requirement.as_list.map { |r| r + '.a' } + additional_requirements.flat_map(&:as_list))
        end

        options = if Pod.match_version?('~> 1.7')
                    podfile.installation_options
                  else
                    installation_options
                  end

        if Pod.match_version?('~> 1.8')
          specifications = find_cached_set(dependency)
                           .all_specifications(options.warn_for_multiple_pod_sources, requirement)
        else
          specifications = find_cached_set(dependency)
                           .all_specifications(options.warn_for_multiple_pod_sources)
                           .select { |s| requirement.satisfied_by? s.version }
        end

        specifications
          .map { |s| s.subspec_by_name(dependency.name, false, true) }
          .compact
      end
    end

    if Pod.match_version?('~> 1.6')
      alias old_valid_possibility_version_for_root_name? valid_possibility_version_for_root_name?

      def valid_possibility_version_for_root_name?(requirement, activated, spec)
        return true if podfile.allow_prerelease?

        old_valid_possibility_version_for_root_name?(requirement, activated, spec)
      end
    elsif Pod.match_version?('~> 1.4')
      def requirement_satisfied_by?(requirement, activated, spec)
        version = spec.version
        return false unless requirement.requirement.satisfied_by?(version)

        shared_possibility_versions, prerelease_requirement = possibility_versions_for_root_name(requirement, activated)
        if !shared_possibility_versions.empty? && !shared_possibility_versions.include?(version)
          return false
        end
        if !podfile.allow_prerelease? && version.prerelease? && !prerelease_requirement
          return false
        end
        unless spec_is_platform_compatible?(activated, requirement, spec)
          return false
        end

        true
      end
    end

    # 读取黑名单
    def read_black_list
      config_file = File.join(Pod::Config.instance.project_root, 'BinConfig.yaml')
      return nil unless File.exist?(config_file)
      config = YAML.load(File.open(config_file))
      return nil if config.nil?
      install_config = config['install_config']
      return nil if install_config.nil?
      install_config['black_list']
    end

    # >= 1.4.0 才有 resolver_specs_by_target 以及 ResolverSpecification
    # >= 1.5.0 ResolverSpecification 才有 source，供 install 或者其他操作时，输入 source 变更
    #
    if Pod.match_version?('~> 1.4')
      old_resolve = instance_method(:resolve)
      define_method(:resolve) do
        dependencies = @podfile_dependency_cache.target_definition_list.flat_map do |target|
          @podfile_dependency_cache.target_definition_dependencies(target).each do |dep|
            next unless target.platform
            @platforms_by_dependency[dep].push(target.platform)
          end
        end.uniq
        @platforms_by_dependency.each_value(&:uniq!)

        # 遍历locked_dependencies，将二进制版本号的最后一位删掉
        locked_dependencies.each do |value|
          next if value.nil?
          # 获取 Pod::Dependency
          dep = value.payload
          next if dep.external_source
          # 修改版本号限制
          requirements = dep.requirement.as_list.map do |req|
            req_arr = req.split('.').delete_if { |r| r.include?('bin') }
            req_arr.join('.')
          end
          # 重新生成 Pod::Dependency
          dep = Dependency.new(dep.name, requirements, {:source => dep.podspec_repo, :external_source => dep.external_source})
          value.payload = dep
        end

        start_time = Time.now
        @activated = Molinillo::Resolver.new(self, self).resolve(dependencies, locked_dependencies)
        UI.puts "Molinillo resolve耗时:#{'%.1f' % (Time.now - start_time)}s".green
        resolver_specs_by_target
      rescue Molinillo::ResolverError => e
        handle_resolver_error(e)
      end

      old_resolver_specs_by_target = instance_method(:resolver_specs_by_target)
      define_method(:resolver_specs_by_target) do
        specs_by_target = old_resolver_specs_by_target.bind(self).call

        sources_manager = Config.instance.sources_manager
        use_source_pods = podfile.use_source_pods

        # 从BinConfig读取black_list
        black_list = read_black_list
        use_source_pods.concat(black_list).uniq! unless black_list.nil?

        specifications = specs_by_target.values.flatten.map(&:spec).uniq

        missing_binary_specs = []
        specs_by_target.each do |target, rspecs|
          # use_binaries 并且 use_source_pods 不包含  本地可过滤
          use_binary_rspecs = if podfile.use_binaries? || podfile.use_binaries_selector
                                rspecs.select do |rspec|
                                  ([rspec.name, rspec.root.name] & use_source_pods).empty? &&
                                    (podfile.use_binaries_selector.nil? || podfile.use_binaries_selector.call(rspec.spec))
                                end
                              else
                                []
                              end

          # Parallel.map(rspecs, in_threads: 8) do |rspec|
          specs_by_target[target] = rspecs.map do |rspec|
            # 含有 subspecs 的组件暂不处理
            # next rspec if rspec.spec.subspec? || rspec.spec.subspecs.any?

            # developments 组件采用默认输入的 spec (development pods 的 source 为 nil)
            # 可以使 :podspec => "htts://IMYFoundation.podspec"可以走下去，by slj
            unless rspec.spec.respond_to?(:spec_source) && rspec.spec.spec_source
              next rspec
            end

            # 采用二进制依赖并且不为开发组件
            use_binary = use_binary_rspecs.include?(rspec)
            if use_binary
              source = sources_manager.binary_source
              configuration = ENV['configuration'] || podfile.configuration
              spec_version = version_helper.version(rspec.root.name, rspec.spec.version, specifications, configuration)
            else
              # 获取podfile中的source
              podfile_sources = podfile.sources.uniq.map { |source| sources_manager.source_with_name_or_url(source) }
              source = (sources_manager.code_source_list + podfile_sources).uniq.select do |s|
                s.search(rspec.root.name)
              end.first
              spec_version = rspec.spec.version
            end

            raise Informative, "#{rspec.root.name}(#{spec_version})的podspec未找到，请执行 pod repo update 或添加相应的source源" unless source

            # UI.message "------------------- 分界线 -----------------------"
            # UI.message "- 开始处理 #{rspec.spec.name}(#{spec_version}) 组件（#{use_binary ? '二进制' : '源码'}）."

            begin
              # 从新 source 中获取 spec,在bin archive中会异常，因为找不到
              specification = source.specification(rspec.root.name, spec_version)

              raise Informative, "Specification of #{rspec.root.name}(#{spec_version}) is nil" unless specification

              UI.message "specification = #{specification}"
              # 组件是 subspec
              if rspec.spec.subspec?
                specification = specification.subspec_by_name(rspec.name, false, true)
              end

              # 这里可能出现分析依赖的 source 和切换后的 source 对应 specification 的 subspec 对应不上
              # 造成 subspec_by_name 返回 nil，这个是正常现象
              next unless specification

              used_by_only = if Pod.match_version?('~> 1.7')
                               rspec.used_by_non_library_targets_only
                             else
                               rspec.used_by_tests_only
                             end
              # 组装新的 rspec ，替换原 rspec
              rspec = if Pod.match_version?('~> 1.4.0')
                        ResolverSpecification.new(specification, used_by_only)
                      else
                        ResolverSpecification.new(specification, used_by_only, source)
                      end
              # UI.message "组装新的 rspec ，替换原 rspec #{rspec.root.name} (#{spec_version}) specification = #{specification} #{rspec} "
            rescue Pod::StandardError => e
              # 没有从新的 source 找到对应版本组件，直接返回原 rspec
              missing_binary_specs << rspec.spec if use_binary
              # UI.message "【#{rspec.spec.name} | #{rspec.spec.version}】组件无对应源码版本 , 将采用二进制版本依赖.".red unless use_binary
              rspec
            end
            rspec
          end.compact
        end

        # if missing_binary_specs.any?
        #   missing_binary_specs.uniq.each do |spec|
        #     # UI.message "【#{spec.name} | #{spec.version}】组件无对应二进制版本 , 将采用源码依赖." unless spec.root.source[:type] == 'zip'
        #   end
        #   # 下面的代码为了实现 auto 命令的 --all-make
        #   Pod::Command::Bin::Archive.missing_binary_specs(missing_binary_specs)
        #   #缓存没有二进制组件到spec文件，local_psec_dir 目录
        #   sources_sepc = []
        #   des_dir = CBin::Config::Builder.instance.local_psec_dir
        #   FileUtils.rm_f(des_dir) if File.exist?des_dir
        #   Dir.mkdir des_dir unless File.exist?des_dir
        #   missing_binary_specs.uniq.each do |spec|
        #     # 排除subspec
        #     next if spec.name.include?('/')
        #
        #     spec_git_res = false
        #     CBin::Config::Builder.instance.ignore_git_list.each do |ignore_git|
        #       spec_git_res = spec.source[:git] && spec.source[:git].include?(ignore_git)
        #       break if spec_git_res
        #     end
        #     next if spec_git_res
        #
        #     #获取没有制作二进制版本的spec集合
        #     sources_sepc << spec
        #     unless spec.defined_in_file.nil?
        #       FileUtils.cp("#{spec.defined_in_file}", "#{des_dir}")
        #     end
        #   end
        # end

        specs_by_target
      end
    end

    def version_helper
      @version_helper ||= begin
                            CBin::BuildAll::BinHelper.new
                          end
    end
  end

  if Pod.match_version?('~> 1.4.0')
    # 1.4.0 没有 spec_source
    class Specification
      class Set
        class LazySpecification < BasicObject
          attr_reader :spec_source

          old_initialize = instance_method(:initialize)
          define_method(:initialize) do |name, version, source|
            old_initialize.bind(self).call(name, version, source)

            @spec_source = source
          end

          def respond_to?(method, include_all = false)
            return super unless method == :spec_source

            true
          end
        end
      end
    end
  end
end
