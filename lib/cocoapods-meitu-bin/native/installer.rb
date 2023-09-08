require 'cocoapods/installer/project_cache/target_metadata.rb'
require 'parallel'
require 'cocoapods'
require 'xcodeproj'
require 'json'
require 'timeout'
require 'net/http'
require 'cocoapods-meitu-bin/native/pod_source_installer'
require 'cocoapods-meitu-bin/helpers/pod_size_helper'
require 'cocoapods-meitu-bin/config/config'

module Pod
  class Installer
    alias mtxx_create_analyzer create_analyzer
    def create_analyzer(plugin_sources = nil)
      # 修复MBox下即使存在Podfile.lock依赖分析依然很慢的问题
      if !lockfile.nil? && lockfile.internal_data.empty?
        @lockfile = Lockfile.from_file(config.lockfile_path) if config.lockfile_path
      end
      mtxx_create_analyzer(plugin_sources)
    end

    def cost_time_hash
      @cost_time_hash ||= begin
                            Hash.new
                          end
    end

    # TODO: 不知道为啥无法hook
    # 准备
    alias old_prepare prepare
    def prepare
      start_time = Time.now
      old_prepare
      cost_time_hash['prepare'] = Time.now - start_time
    end

    # 依赖分析
    alias old_resolve_dependencies resolve_dependencies
    def resolve_dependencies
      start_time = Time.now
      list =  PodUpdateConfig.pods
      # 判断  PodUpdateConfig.pods 是否为空，且数组大于0
      if list && !list.empty?
        self.update = { :pods => list  }
      end
      if PodUpdateConfig.lockfile
        self.instance_variable_set("@lockfile",PodUpdateConfig.lockfile)
      end
      if PodUpdateConfig.is_clear
        self.instance_variable_set("@lockfile",PodUpdateConfig.lockfile)
      end

      plugin_sources = run_source_provider_hooks
      analyzer = create_analyzer(plugin_sources)

      UI.section 'Updating local specs repositories' do
        analyzer.update_repositories
      end if repo_update? && PodUpdateConfig.repo_update

      UI.section 'Analyzing dependencies' do
        analyze(analyzer)
        validate_build_configurations
      end

      UI.section 'Verifying no changes' do
        verify_no_podfile_changes!
        verify_no_lockfile_changes!
      end if deployment?
      cost_time_hash['prepare'] = PodUpdateConfig.prepare_time
      cost_time_hash['resolve_dependencies'] = Time.now - start_time
      analyzer
    end

    # 依赖下载
    alias old_download_dependencies download_dependencies
    def download_dependencies
      start_time = Time.now
      old_download_dependencies
      cost_time_hash['download_dependencies'] = Time.now - start_time
    end

    # 验证target
    alias old_validate_targets validate_targets
    def validate_targets
      start_time = Time.now
      old_validate_targets
      cost_time_hash['validate_targets'] = Time.now - start_time
    end

    # 集成
    alias old_integrate integrate
    def integrate
      start_time = Time.now
      old_integrate
      cost_time_hash['integrate'] = Time.now - start_time
    end

    # 写入lock文件
    def write_lockfiles
      start_time = Time.now
      @lockfile = generate_lockfile

      UI.message "- Writing Lockfile in #{UI.path config.lockfile_path}" do
        # No need to invoke Sandbox#update_changed_file here since this logic already handles checking if the
        # contents of the file are the same.
        @lockfile.write_to_disk(config.lockfile_path)
      end

      UI.message "- Writing Manifest in #{UI.path sandbox.manifest_path}" do
        # No need to invoke Sandbox#update_changed_file here since this logic already handles checking if the
        # contents of the file are the same.
        @lockfile.write_to_disk(sandbox.manifest_path)
      end
      cost_time_hash['write_lockfiles'] = Time.now - start_time
    end

    # 执行post install
    alias old_perform_post_install_actions perform_post_install_actions
    def perform_post_install_actions
      start_time = Time.now
      old_perform_post_install_actions
      source_pods = []
      bin_pods = []
      @pod_targets.map do |target|
        if target.should_build?
          source_pods << target
        else
          bin_pods << target
        end
      end
      cost_time_hash['perform_post_install_actions'] = Time.now - start_time

      # 打印有多少个源码库，多少二进制库
      print_source_bin_statistics(source_pods,bin_pods)
      # 打印耗时
      print_cost_time
      # 打印大小大于阈值的库
      CBin::PodSize.print_pods
      if PodUpdateConfig.is_mtxx
        begin
          data = {
            "meitu_bin_version" => CBin::VERSION,
            "large_pod_hash" => PodUpdateConfig.large_pod_hash
          }
          all_time = 0
          cost_time_hash.each do |key, value|
            time = ('%.1f' % value).to_f
            data[key] = time
            all_time = all_time + time
          end
          data["pod_time"] = all_time
          binary_rate = bin_pods.size.to_f / @pod_targets.size.to_f
          data["binary_rate"] = ('%.2f' % binary_rate).to_f
          data["source_count"] = source_pods.size
          data["binary_count"] = bin_pods.size
          data["targets_count"] = @pod_targets.size
          source = "unknown user"
          if ENV['NODE_NAME']
            source = ENV['NODE_NAME']
          else
            source = `git config user.email`
            source = source.gsub("\n", "")
          end
          data_json = {
            "subject" => "MTXX pod time profiler",
            "type" => "pod_time_profiler",
            "source" => source,
            "data" => data
          }
          begin
            Timeout.timeout(3) do
              json_data = [data_json].to_json
              api_url = "http://event-adapter-internal.prism.cloud.meitu-int.com/api/v1/http/send/batch"
              headers = { "Content-Type" => "application/json" }
              uri = URI(api_url)
              http = Net::HTTP.new(uri.host, uri.port)
              request = Net::HTTP::Post.new(uri.path, headers)
              request.body = json_data
              response = http.request(request)
              if ENV['MEITU_USE_POD_SOURCE'] == '1'
                puts "pod_time_profiler: Response code: #{response.code}"
                puts "pod_time_profiler: data_json: #{data_json}"
              end
            end
          rescue Timeout::Error
            puts "pod_time_profiler: 上报pod操作操作已超时"
          end
        rescue => error
          puts "pod_time_profiler: 上报pod 耗时统计失败，失败原因：#{error}"
        end
      end

    end

    # 打印有多少个源码库，多少二进制库
    def print_source_bin_statistics(source_pods,bin_pods)

      UI.puts "\npod_time_profiler: 总共有 #{@pod_targets.size} 个Pod库，二进制有 #{bin_pods.size} 个，源码有 #{source_pods.size} 个".green
      # 打印二进制库
      if ENV['statistics_bin'] == '1'
        UI.puts "二进制库：".green
        UI.puts bin_pods
      end
      # 打印源码库
      if ENV['MEITU_USE_POD_SOURCE'] == '1'
        UI.puts "源码库：".green
        source_pods.each do |pod|
          UI.puts "pod_time_profiler: #{pod.name}"
        end
      end
    end

    # 打印耗时
    def print_cost_time
      prefix = 'pod_time_profiler:'
      UI.title "#{prefix} pod执行耗时：".green do
        UI.info "#{prefix} ———————————————————————————————————————————————".green
        UI.info "#{prefix} |#{'Stage'.center(30)}|#{'Time(s)'.center(15)}|".green
        UI.info "#{prefix} ———————————————————————————————————————————————".green
        cost_time_hash.each do |key, value|
          UI.info "#{prefix} |#{key.center(30)}|#{('%.3f' % value).to_s.center(15)}|".green
        end
        UI.info "#{prefix} ———————————————————————————————————————————————".green
      end
    end

    alias old_create_pod_installer create_pod_installer
    def create_pod_installer(pod_name)
      installer = old_create_pod_installer(pod_name)
      installer.installation_options = installation_options
      installer
    end

    alias old_install_pod_sources install_pod_sources
    def install_pod_sources
      if installation_options.install_with_multi_threads
        install_pod_sources_with_multiple_threads
      else
        old_install_pod_sources
      end
    end

    # 多线程下载
    def install_pod_sources_with_multiple_threads
      @installed_specs = []
      pods_to_install = sandbox_state.added | sandbox_state.changed
      title_options = { :verbose_prefix => '-> '.green }
      thread_count = installation_options.multi_threads_count
      Parallel.each(root_specs.sort_by(&:name), in_threads: thread_count) do |spec|
        if pods_to_install.include?(spec.name)
          if sandbox_state.changed.include?(spec.name) && sandbox.manifest
            current_version = spec.version
            previous_version = sandbox.manifest.version(spec.name)
            has_changed_version = current_version != previous_version
            current_repo = analysis_result.specs_by_source.detect { |key, values| break key if values.map(&:name).include?(spec.name) }
            current_repo &&= (Pod::TrunkSource::TRUNK_REPO_NAME if current_repo.name == Pod::TrunkSource::TRUNK_REPO_NAME) || current_repo.url || current_repo.name
            previous_spec_repo = sandbox.manifest.spec_repo(spec.name)
            has_changed_repo = !previous_spec_repo.nil? && current_repo && !current_repo.casecmp(previous_spec_repo).zero?
            title = "Installing #{spec.name} #{spec.version}"
            title << " (was #{previous_version} and source changed to `#{current_repo}` from `#{previous_spec_repo}`)" if has_changed_version && has_changed_repo
            title << " (was #{previous_version})" if has_changed_version && !has_changed_repo
            title << " (source changed to `#{current_repo}` from `#{previous_spec_repo}`)" if !has_changed_version && has_changed_repo
          else
            title = "Installing #{spec}"
          end
          UI.titled_section(title.green, title_options) do
            install_source_of_pod(spec.name)
          end
        else
          UI.section("Using #{spec}", title_options[:verbose_prefix]) do
            create_pod_installer(spec.name)
          end
        end
      end
    end

    # alias old_write_lockfiles write_lockfiles
    # def write_lockfiles
    #   old_write_lockfiles
    #   if File.exist?('Podfile_local')
    #
    #     project = Xcodeproj::Project.open(config.sandbox.project_path)
    #     #获取主group
    #     group = project.main_group
    #     group.set_source_tree('SOURCE_ROOT')
    #     #向group中添加 文件引用
    #     file_ref = group.new_reference(config.sandbox.root + '../Podfile_local')
    #     #podfile_local排序
    #     podfile_local_group = group.children.last
    #     group.children.pop
    #     group.children.unshift(podfile_local_group)
    #     #保存
    #     project.save
    #   end
    # end
  end

  module Downloader
    class Cache
      require 'cocoapods-meitu-bin/helpers/pod_size_helper'
      # 多线程锁
      @@lock = Mutex.new

      # 后面如果要切到进程的话，可以在 cache root 里面新建一个文件
      # 利用这个文件 lock
      # https://stackoverflow.com/questions/23748648/using-fileflock-as-ruby-global-lock-mutex-for-processes

      # rmtree 在多进程情况下可能  Directory not empty @ dir_s_rmdir 错误
      # old_ensure_matching_version 会移除不是同一个 CocoaPods 版本的组件缓存
      alias old_ensure_matching_version ensure_matching_version
      def ensure_matching_version
        @@lock.synchronize do
          version_file = root + 'VERSION'
          # version = version_file.read.strip if version_file.file?

          # root.rmtree if version != Pod::VERSION && root.exist?
          root.mkpath

          version_file.open('w') { |f| f << Pod::VERSION }
        end
      end

      def uncached_pod(request)
        in_tmpdir do |target|
          result, podspecs = download(request, target)
          result.location = nil

          # 记录下载大小大于阈值的库及大小
          if File.exist?(target.to_s)
            dir_size = `du -sk #{target.to_s}`.strip().split(' ')[0]
            CBin::PodSize.add_pod({:name => request.name, :size => dir_size})
          end

          podspecs.each do |name, spec|
            destination = path_for_pod(request, :name => name, :params => result.checkout_options)
            copy_and_clean(target, destination, spec)
            write_spec(spec, path_for_spec(request, :name => name, :params => result.checkout_options))
            if request.name == name
              result.location = destination
            end
          end

          result
        end
      end
    end
  end
end
