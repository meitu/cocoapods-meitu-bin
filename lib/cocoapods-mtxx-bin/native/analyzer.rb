
require 'parallel'
require 'cocoapods'

module Pod
  class Installer
    class Analyzer
      alias old_fetch_external_sources fetch_external_sources
      def fetch_external_sources(podfile_state)
        verify_no_pods_with_different_sources!
        deps = dependencies_to_fetch(podfile_state)
        pods = pods_to_fetch(podfile_state)
        return if deps.empty?
        UI.section 'Fetching external sources' do
          if installation_options.install_with_multi_threads
            thread_count = installation_options.multi_threads_count
            Parallel.each(deps.sort, in_threads: thread_count) do |dependency|
              fetch_external_source(dependency, !pods.include?(dependency.root_name))
            end
          else
            deps.sort.each do |dependency|
              fetch_external_source(dependency, !pods.include?(dependency.root_name))
            end
          end
        end
      end

      # > 1.6.0
      # all_specs[dep.name] 为 nil 会崩溃
      # 主要原因是 all_specs 分析错误
      # 查看 source 是否正确
      #
      # def dependencies_for_specs(specs, platform, all_specs)
      #   return [] if specs.empty? || all_specs.empty?

      #   dependent_specs = Set.new

      #   specs.each do |s|
      #     s.dependencies(platform).each do |dep|
      #       all_specs[dep.name].each do |spec|
      #         dependent_specs << spec
      #       end
      #     end
      #   end

      #   dependent_specs - specs
      # end

      # > 1.5.3 版本
      # rewrite update_repositories
      #
      alias old_update_repositories update_repositories
      def update_repositories
        if installation_options.update_source_with_multi_threads
          # 并发更新私有源
          # 这里多线程会导致 pod update 额外输出 --verbose 的内容
          # 不知道为什么？
          thread_count = installation_options.multi_threads_count
          Parallel.each(sources.uniq(&:url), in_threads: thread_count) do |source|
            if source.updateable?
              sources_manager.update(source.name, true)
            else
              UI.message "Skipping `#{source.name}` update because the repository is not an updateable repository."
            end
          end
          @specs_updated = true
        else
          old_update_repositories
        end
      end

      # 解决 dep.name = xxx/binary 时，all_specs[dep.name] 返回nil，导致调用 each 方法报错
      alias old_dependencies_for_specs dependencies_for_specs
      def dependencies_for_specs(specs, platform, all_specs)
        dependent_specs = {
          :debug => Set.new,
          :release => Set.new,
        }

        podfile = Pod::Config.instance.podfile

        if !specs.empty? && !all_specs.empty?
          specs.each do |s|
            s.dependencies(platform).each do |dep|
              # use_binary = podfile.use_binaries? && !podfile.use_source_pods.include?(dep.root_name)
              # key = use_binary ? dep.root_name : dep.name
              all_specs[dep.name].each do |spec|
                if spec.non_library_specification?
                  if s.test_specification? && spec.name == s.consumer(platform).app_host_name && spec.app_specification?
                    # This needs to be handled separately, since we _don't_ want to treat this as a "normal" dependency
                    next
                  end
                  raise Informative, "`#{s}` depends upon `#{spec}`, which is a `#{spec.spec_type}` spec."
                end

                dependent_specs.each do |config, set|
                  next unless s.dependency_whitelisted_for_configuration?(dep, config)
                  set << spec
                end
              end unless all_specs[dep.name].nil? # 解决 dep.name = xxx/binary 时，all_specs[dep.name]返回的是nil，导致调用 each 方法报错
            end
          end
        end

        Hash[dependent_specs.map { |k, v| [k, (v - specs).group_by(&:root)] }].freeze
      end
    end
  end
end
