
module CBin
  module BuildAll
    class PodspecUtil
      include Pod

      def initialize(pod_target, version, build_as_framework = false, configuration = 'Debug')
        @pod_target = pod_target
        @version = version
        @build_as_framework = build_as_framework
        @configuration = configuration
      end

      # 创建二进制podspec
      def create_binary_podspec
        UI.info "创建二进制podspec：`#{@pod_target}`".yellow
        spec = @pod_target.root_spec.to_hash
        root_dir = @pod_target.framework_name
        # 处理版本号
        spec['version'] = version
        # 处理source
        spec['source'] = source
        # 处理头文件
        spec['source_files'] = "#{root_dir}/Headers/*.h"
        spec['public_header_files'] = "#{root_dir}/Headers/*.h"
        spec['private_header_files'] = "#{root_dir}/PrivateHeaders/*.h"
        # 处理vendored_libraries和vendored_frameworks
        spec['vendored_libraries'] = "#{root_dir}/libs/*.a"
        #兼容.xcframework
        spec['vendored_frameworks'] = %W[#{root_dir} #{root_dir}/fwks/*.framework #{root_dir}/fwks/*.xcframework]
        # 处理资源
        resources = %W[#{root_dir}/*.{#{special_resource_exts.join(',')}} #{root_dir}/resources/*]
        spec['resources'] = resources
        # 删除无用的字段
        delete_unused(spec)
        # 处理subspecs
        handle_subspecs(spec)
        # 生成二进制podspec
        bin_spec = Pod::Specification.from_hash(spec)
        bin_spec.description = <<-EOF
         「converted automatically by plugin cocoapods-meitu-bin @美图 - zys」
          #{bin_spec.description}
        EOF
        bin_spec
        # puts bin_spec.to_json
      end

      # podspec写入文件
      def write_binary_podspec(spec)
        UI.info "写入podspec：`#{@pod_target}`".yellow
        podspec_dir = "#{Pathname.pwd}/build_pods/#{@pod_target}/Products/podspec"
        FileUtils.mkdir(podspec_dir) unless File.exist?(podspec_dir)
        file = "#{podspec_dir}/#{@pod_target.pod_name}.podspec.json"
        FileUtils.rm_rf(file) if File.exist?(file)

        File.open(file, "w+") do |f|
          f.write(spec.to_pretty_json)
        end
        file
      end

      # 上传二进制podspec
      def push_binary_podspec(binary_podsepc_json)
        UI.info "推送podspec：`#{@pod_target}`".yellow
        return unless File.exist?(binary_podsepc_json)
        repo_name = Pod::Config.instance.sources_manager.binary_source.name
        # repo_name = 'example-private-spec-bin'
        argvs = %W[#{repo_name} #{binary_podsepc_json} --skip-import-validation --use-libraries --allow-warnings --verbose]

        begin
          push = Pod::Command::Repo::Push.new(CLAide::ARGV.new(argvs))
          push.validate!
          push.run
          return true
        rescue Pod::StandardError => e
          UI.info "推送podspec：`#{@pod_target}`失败，#{e.to_s}".red
          return false
        end
      end

      private

      # 删除无用的字段
      def delete_unused(spec)
        spec.delete('project_header_files')
        spec.delete('resource_bundles')
        spec.delete('exclude_files')
        spec.delete('preserve_paths')
        spec.delete('prepare_command')
      end

      # 处理subspecs
      def handle_subspecs(spec)
        spec['subspecs'].map do |subspec|
          # 处理单个subspec
          handle_single_subspec(subspec, spec)
          # 递归处理subspec
          recursive_handle_subspecs(subspec['subspecs'], spec)
        end if spec && spec['subspecs']
      end

      # 递归处理subspecs
      def recursive_handle_subspecs(subspecs, spec)
        subspecs.map do |s|
          # 处理单个subspec
          handle_single_subspec(s, spec)
          # 递归处理
          recursive_handle_subspecs(s['subspecs'], spec)
        end if subspecs
      end

      # 处理单个subspec
      def handle_single_subspec(subspec, spec)
        subspec['source_files'] = spec['source_files']
        subspec['public_header_files'] = spec['public_header_files']
        subspec['private_header_files'] = spec['private_header_files']
        subspec['vendored_frameworks'] = spec['vendored_frameworks']
        subspec['vendored_libraries'] = spec['vendored_libraries']
        subspec['resources'] = spec['resources']
        # 删除无用字段
        delete_unused(subspec)
      end

      def source
        # url = "http://localhost:8080/frameworks/#{BinHelper.xcode_version}/#{@pod_target.root_spec.module_name}/#{version}/zip"
        url = "#{CBin.config.binary_download_url_str}/#{BinHelper.xcode_version}/#{@configuration}/#{@pod_target.root_spec.module_name}/#{version}/#{@pod_target.framework_name}_#{version}.zip"
        { http: url, type: CBin.config.download_file_type }
      end

      def version
        @version || @pod_target.root_spec.version
      end

      # 特殊的资源后缀
      def special_resource_exts
        %w[momd mom cdm nib storyboardc]
      end

    end
  end
end
