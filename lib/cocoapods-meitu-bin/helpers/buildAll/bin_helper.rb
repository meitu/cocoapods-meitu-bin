require 'digest'

module CBin
  module BuildAll
    class BinHelper
      include Pod

      def initialize
        super
        @specs_str_md5_hash = Hash.new
      end

      # 二进制版本号（x.y.z.bin[md5前6位]）
      def version(pod_name, original_version, specifications, configuration = 'Debug', include_dependencies = false)
        # 有缓存从缓存中取，没有则新建
        if @specs_str_md5_hash[pod_name].nil?
          specs = specifications.map(&:name).select { |spec|
            spec.include?(pod_name) && !spec.include?('/Binary')
          }.sort!
          # puts "#{pod_name}:#{include_dependencies}"
          if include_dependencies
            specs << dependencies_str(pod_name, specifications)
          end
          specs << xcode_version
          specs << (configuration.nil? ? 'Debug' : configuration)
          specs_str = specs.join('')
          if ENV['p_bin_v'] == '1'
            UI.puts "`#{pod_name}`：#{specs_str}".red
          end
          specs_str_md5 = Digest::MD5.hexdigest(specs_str)[0,6]
          @specs_str_md5_hash[pod_name] = specs_str_md5
        else
          specs_str_md5 = @specs_str_md5_hash[pod_name]
        end
        "#{original_version}.bin#{specs_str_md5}"
      end

      def xcode_version
        @xcode_version ||= begin
                             `xcodebuild -version`.split(' ').join('')
                           end
      end
      
      def self.xcode_version
          xcode_version = `xcodebuild -version`.split(' ').join('')
          xcode_version
      end

      # 将当前 Pod 库的依赖库拼接成字符串（格式：pod1_name(pod1_version),pod2_name(pod2_version),...）
      def dependencies_str(pod_name, specifications)
        deps = []
        specifications.map do |spec|
          if spec.root.name == pod_name
            deps.concat(spec.dependencies)
          end
        end
        if deps.empty?
          UI.puts "`#{pod_name}`无依赖库".red if ENV['p_bin_d'] == '1'
          return ''
        end
        result = []
        deps.uniq.map do |dep|
          if dep.root_name == pod_name
            next
          end
          version = dep_version(dep, specifications)
          result << "#{dep.name}(#{version})"
        end
        if ENV['p_bin_d'] == '1'
          if result.empty?
            UI.puts "`#{pod_name}`无依赖库".red
          else
            UI.puts "`#{pod_name}`依赖的库如下：".yellow
            result.map { |pod| puts "- #{pod}" }
          end
        end
        result.join(',')
      end

      # 获取依赖库版本号
      def dep_version(dep, specifications)
        version = ''
        specifications.map do |spec|
          if spec.root.name == dep.root_name
            version = spec.root.version.to_s
            # 如果是二进制版本，去掉二进制版本号后缀
            version_arr = version.split('.')
            if version_arr.last.include?('bin')
              version_arr.delete_at(version_arr.size - 1)
              version = version_arr.join('.')
            end
            break
          end
        end
        version
      end

    end
  end
end
