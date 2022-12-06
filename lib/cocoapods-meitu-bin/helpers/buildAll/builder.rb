
module CBin
  module BuildAll
    class Builder
      include Pod

      def initialize(pod_target, checkout_sources, skip_simulator = false, configuration = 'Debug')
        @pod_target = pod_target
        @checkout_sources = checkout_sources
        @skip_simulator = skip_simulator
        @configuration = configuration
        @file_accessors = pod_target.file_accessors unless pod_target.nil?
        @base_dir = "#{Pathname.pwd}/build_pods"
      end

      # 构建
      def build
        UI.info "编译`#{@pod_target}`".yellow
        dir = result_product_dir
        FileUtils.rm_rf(dir) if File.exist?(dir)
        # 编译模拟器
        unless @skip_simulator
          result = build_pod_target
          return false unless result
        end
        # 编译真机
        build_pod_target(false)
      end

      # 创建binary
      def create_binary
        UI.info "创建`#{@pod_target.framework_name}`".yellow
        # 如果是framework需要先copy
        if build_as_framework?
          copy_framework
        else
          create_framework_dir
          copy_headers
          copy_headers(false )
          generate_umbrella_header
          generate_module_map
          compile_resources
          if @pod_target.uses_swift?
            copy_iphoneos_swiftmodules
            copy_simulator_swiftmodules unless @skip_simulator
          end
          if @skip_simulator
            device_lib = "#{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target.static_library_name}"
            output = "#{result_product_dir}/#{@pod_target.product_module_name}"
            `cp -f #{device_lib} #{output}`
          end
        end
        # 合并真机模拟器
        merge_device_sim unless @skip_simulator
        # 拷贝资源文件
        copy_resources
        # 拷贝 vendored_frameworks 和 vendored_libraries
        copy_vendored_frameworks
        copy_vendored_libraries
      end

      # 是否以framework形式构建
      def build_as_framework?
        path = "#{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target.framework_name}"
        File.exist?(path)
      end

      # xxx.framework/Modules
      def modules_dir
        "#{result_product_dir}/Modules"
      end

      # xxx.framework/Headers
      def headers_dir
        "#{result_product_dir}/Headers"
      end

      # xxx.framework/PrivateHeaders
      def private_headers_dir
        "#{result_product_dir}/PrivateHeaders"
      end

      # xxx.framework/resources
      def resources_dir
        "#{result_product_dir}/resources"
      end

      # xxx.framework
      def result_product_dir
        "#{product_dir}/#{@pod_target.framework_name}"
      end

      # xxx.framework 所在目录
      def product_dir
        @product_dir = "#{@base_dir}/#{@pod_target}/Products"
        @product_dir
      end

      # 构建临时产物目录
      def temp_dir
        "#{@base_dir}/#{@pod_target}/Temp"
      end

      def iphoneos
        "#{@configuration}-iphoneos"
      end

      def iphonesimulator
        "#{@configuration}-iphonesimulator"
      end

      # 需要排除的资源文件后缀
      def reject_resource_ext
        %w[.xcdatamodeld .xcdatamodel .xcmappingmodel .xib .storyboard]
      end

      private

      # 加载当前 target 的 build_settings
      def load_target_build_settings(project, target)
        @build_settings ||= begin
                              command = <<-BUILDSETTINGS
xcodebuild \
-target #{target} \
-project #{project} \
-showBuildSettings \
-configuration #{@configuration}
                              BUILDSETTINGS
                              output = `#{command}`
                              # 删除临时文件夹 build，防止出现 clean failed
                              FileUtils.rm_rf("#{Pod::Config.instance.installation_root}/build")
                              output
                            end
      end

      # 加载具体某个 build_setting
      def load_single_build_setting(project, target, key)
        build_settings = load_target_build_settings(project, target)
        flags = `echo '#{build_settings}' | grep #{key}`
        if flags.size > 0
          flags = flags.split("#{key} =")
          if flags.size == 2
            flags = flags.last
          end
        end
        flags.strip
      end

      # 构建单个pod
      def build_pod_target(simulator = true)
        sdk = simulator ? 'iphonesimulator' : 'iphoneos'
        archs = simulator ? 'x86_64' : 'arm64'
        product_dir = product_dir()
        temp_dir = temp_dir()
        pod_project_path = Dir.pwd + "/Pods/#{@pod_target}.xcodeproj"
        if File.exist?(pod_project_path)
          project = "./Pods/#{@pod_target}.xcodeproj"
        else
          project = "./Pods/Pods.xcodeproj"
        end

        other_c_flags = load_single_build_setting(project, @pod_target, 'OTHER_CFLAGS')
        other_c_flags += " -fdebug-prefix-map=#{Pod::Config.instance.sandbox_root}=."
        other_swift_flags = load_single_build_setting(project, @pod_target, 'OTHER_SWIFT_FLAGS')
        other_swift_flags += " -debug-prefix-map #{Pod::Config.instance.sandbox_root}=."

        command = <<-BUILD
xcodebuild GCC_PREPROCESSOR_DEFINITIONS='$(inherited)' \
GCC_WARN_INHIBIT_ALL_WARNINGS=YES \
CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES \
-sdk #{sdk} \
ARCHS=#{archs} \
CONFIGURATION_TEMP_DIR=#{temp_dir} \
BUILD_ROOT=#{product_dir} \
BUILD_DIR=#{product_dir} \
OTHER_CFLAGS="#{other_c_flags}" \
OTHER_SWIFT_FLAGS="#{other_swift_flags}" \
clean build \
-configuration #{@configuration} \
-target #{@pod_target} \
-project #{project}
        BUILD
        UI.info "#{command}"
        output = `#{command}`
        if $CHILD_STATUS.exitstatus != 0
          UI.info "`#{@pod_target}(#{sdk})`编译失败！".red
          error_log_file = "#{temp_dir}/#{@pod_target}_error.log"
          File.open(error_log_file, "w+") do |f|
            f.write(output)
          end
          return false
        end
        return true
      end

      # 合并真机模拟器
      def merge_device_sim
        if build_as_framework?
          device_lib_dir = "#{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target.framework_name}/#{@pod_target.product_module_name}"
          sim_lib_dir = "#{product_dir}/#{iphonesimulator}/#{@pod_target}/#{@pod_target.framework_name}/#{@pod_target.product_module_name}"
        else
          device_lib_dir = "#{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target.static_library_name}"
          sim_lib_dir = "#{product_dir}/#{iphonesimulator}/#{@pod_target}/#{@pod_target.static_library_name}"
        end
        output = "#{result_product_dir}/#{@pod_target.product_module_name}"
        libs = [device_lib_dir, sim_lib_dir]
        FileUtils.mkdir(result_product_dir) unless File.exist?(result_product_dir)
        `lipo -create -output #{output} #{libs.join(' ')}` unless libs.empty?
      end

      # 创建 xxx.framework 文件夹
      def create_framework_dir
        fwk_path = "#{product_dir}/#{@pod_target.product_module_name}.framework"
        FileUtils.rm_rf(fwk_path) if File.exist?(fwk_path)
        FileUtils.mkdir(fwk_path)
      end

      # -------------------------- 编译需要编译的资源 --------------------------------

      # 需要编译的资源
      def need_compile_resources
        return [] if @file_accessors.nil?
        resources = @file_accessors.flat_map(&:resources)
        return [] if resources.nil? || resources.size == 0
        resources.compact.select { |res| reject_resource_ext.include?(res.extname) }.map(&:to_s)
      end

      # 编译需要编译的资源
      def compile_resources
        resources = need_compile_resources
        resources.map { |res| compile_resource(res) }
      end

      # 编译单个资源
      def compile_resource(resource)
        return unless File.exist?(resource)
        case File.extname(resource)
        when '.storyboard', '.xib'
          compile_storyboard_xib(resource)
        when '.xcdatamodeld', '.xcdatamodel'
          compile_xcdatamodel(resource)
        when '.xcmappingmodel'
          compile_xcmappingmodel(resource)
        end
      end

      # 编译storyboard、xib
      def compile_storyboard_xib(resource)
        file_ext = File.extname(resource)
        file_name = File.basename(resource, file_ext)
        command = <<-COMMAND
ibtool \
--reference-external-strings-file \
--errors --warnings \
--notices \
--output-format human-readable-text \
--compile #{result_product_dir}/#{file_name}.#{file_ext == '.storyboard' ? 'storyboardc' : 'nib'} #{resource} \
--target-device ipad --target-device iphone
        COMMAND
        `#{command}`
      end

      # 编译xcdatamodel、xcdatamodeld
      def compile_xcdatamodel(resource)
        file_ext = File.extname(resource)
        file_name = File.basename(resource, file_ext)
        `xcrun momc #{resource} #{result_product_dir}/#{file_name}.#{file_ext == 'xcdatamodeld' ? 'momd' : 'mom'}`
      end

      # 编译xcmappingmodel
      def compile_xcmappingmodel(resource)
        file_ext = File.extname(resource)
        file_name = File.basename(resource, file_ext)
        `xcrun mapc #{resource} #{result_product_dir}/#{file_name}.cdm`
      end

      # -------------------------- 拷贝头文件、资源等 --------------------------------

      # 拷贝头文件
      def copy_headers(public = true)
        if public
          headers = @file_accessors.map(&:public_headers).flatten.compact.uniq
          header_dir = headers_dir
          if @pod_target.uses_swift?
            umbrella_header = "#{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target}-umbrella.h"
            swift_header = "#{product_dir}/#{iphoneos}/#{@pod_target}/Swift Compatibility Header/#{@pod_target.product_module_name}-Swift.h"
            headers.concat([umbrella_header, swift_header])
          end
        else
          headers = @file_accessors.map(&:private_headers).flatten.compact.uniq
          header_dir = private_headers_dir
        end
        return if headers.empty?
        FileUtils.mkdir(header_dir) unless File.exist?(header_dir)
        headers.map do |header|
          header_path = header
          if header.is_a?(String)
            header_path = header.gsub(/ /, '\ ') if header.include?(' ')
          elsif header.is_a?(Pathname)
            header_path = header.to_s.gsub(/ /, '\ ') if header.to_s.include?(' ')
          end
          `cp -f #{header_path} #{header_dir}`
        end
      end

      # 获取podspec中的resource_bundles
      def resource_bundles
        return [] if @file_accessors.nil?
        resource_bundles = @file_accessors.flat_map(&:resource_bundles)
        return [] if resource_bundles.nil? || resource_bundles.size == 0
        resource_bundles.compact.flat_map(&:keys).map { |key| "#{product_dir}/#{iphoneos}/#{@pod_target}/#{key}.bundle" }
      end

      # 获取podspec中resource/resources
      def other_resources
        return [] if @file_accessors.nil?
        resources = @file_accessors.flat_map(&:resources)
        return [] if resources.nil? || resources.size == 0
        resources.compact.reject { |res| reject_resource_ext.include?(res.extname) }.map(&:to_s)
      end

      # 拷贝资源文件
      def copy_resources
        resources = resource_bundles + other_resources
        return if resources.empty?
        resources_dir = "#{result_product_dir}/resources"
        FileUtils.mkdir(resources_dir) unless File.exist?(resources_dir)
        resources.uniq.map do |resource|
          `rsync -av #{resource} #{resources_dir}`
        end
      end

      # 拷贝 vendored_libraries
      def copy_vendored_libraries
        libs = @pod_target.file_accessors.map(&:vendored_libraries).flatten.compact.uniq
        return if libs.empty?
        libs_dir = "#{result_product_dir}/libs"
        FileUtils.mkdir(libs_dir) unless File.exist?(libs_dir)
        libs.map do |lib|
          `rsync -av #{lib} #{libs_dir}`
        end
      end

      # 拷贝 vendored_frameworks
      def copy_vendored_frameworks
        fwks = @pod_target.file_accessors.map(&:vendored_frameworks).flatten.compact.uniq
        return if fwks.empty?
        fwks_dir = "#{result_product_dir}/fwks"
        FileUtils.mkdir(fwks_dir) unless File.exist?(fwks_dir)
        fwks.map do |fwk|
          `rsync -av #{fwk} #{fwks_dir}`
        end
      end

      # 拷贝 framework
      def copy_framework
        source_path = "#{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target.framework_name}"
        if File.exist?(source_path)
          `rsync -av #{source_path} #{product_dir}`
        end
        # 如果包含Swift代码且需要编译模拟器，则copy模拟器swiftmodules
        if @pod_target.uses_swift?
          copy_simulator_swiftmodules unless @skip_simulator
        end
      end

      # 拷贝真机swiftmodules（只用于static library）
      def copy_iphoneos_swiftmodules
        FileUtils.mkdir(modules_dir) unless File.exist?(modules_dir)
        `cp -rf #{product_dir}/#{iphoneos}/#{@pod_target}/#{@pod_target.product_module_name}.swiftmodule #{modules_dir}`
      end

      # 拷贝模拟器swiftmodules
      def copy_simulator_swiftmodules
        target_swift_module = "#{modules_dir}/#{@pod_target.product_module_name}.swiftmodule"
        if build_as_framework?
          src_swift_module = "#{product_dir}/#{iphonesimulator}/#{@pod_target}/#{@pod_target.framework_name}/Modules/#{@pod_target.product_module_name}.swiftmodule"
        else
          src_swift_module = "#{product_dir}/#{iphonesimulator}/#{@pod_target}/#{@pod_target.product_module_name}.swiftmodule"
        end
        if File.exist?(target_swift_module)
          `cp -af #{src_swift_module}/* #{target_swift_module}`
          `cp -af #{src_swift_module}/Project/* #{target_swift_module}/Project`
        end
      end

      # -------------------------- clang module --------------------------------

      # 生成 module map
      def generate_module_map
        module_map = "#{modules_dir}/module.modulemap"
        FileUtils.mkdir(modules_dir) unless File.exist?(modules_dir)
        FileUtils.rm_f(module_map) if File.exist?(module_map)
        File.open(module_map, "w+") do |f|
          content = <<-MODULEMAP
framework module #{@pod_target.product_module_name} {
  umbrella header "#{@pod_target}-umbrella.h"

  export *
  module * { export * }
}
          MODULEMAP
          # 有Swift代码
          if @pod_target.uses_swift?
            content += <<-SWIFT

module #{@pod_target.product_module_name}.Swift {
  header "#{@pod_target.product_module_name}-Swift.h"
  requires objc
}
            SWIFT
          end
          f.write(content)
        end
      end

      # 生成 umbrella header
      def generate_umbrella_header
        umbrella_header_path = "#{headers_dir}/#{@pod_target}-umbrella.h"
        return if File.exist?(umbrella_header_path)

        umbrella_header = Pod::Generator::UmbrellaHeader.new(@pod_target)
        # 需要导入的头文件
        umbrella_header.imports = @file_accessors.flat_map(&:public_headers).compact.uniq.map { |header| header.basename }
        FileUtils.mkdir(headers_dir) unless File.exist?(headers_dir)
        result = umbrella_header.generate
        File.open(umbrella_header_path, "w+") do |f|
          f.write(result)
        end
      end

    end
  end
end
