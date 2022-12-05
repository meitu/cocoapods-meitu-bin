require 'cocoapods-mtxx-bin/command/bin/source/add'
require 'cocoapods-mtxx-bin/command/bin/source/list'
require 'cocoapods-mtxx-bin/command/bin/source/delete'

module Pod
  class Command
    class Bin < Command
      class Source < Bin
        self.abstract_command = true
        self.summary = '管理二进制对应的源码'
        self.default_subcommand = 'list'

        # 目标路径
        def target_path(source_spec)
          "#{source_dir}/#{source_spec.name}/#{source_spec.version}"
        end

        # 存放源码的根目录
        def source_dir
          @source_dir ||= begin
                            dir = "#{Dir.home}/LLDB_Sources"
                            FileUtils.mkdir_p(dir) unless File.exist?(dir)
                            dir
                          end
        end
      end
    end
  end
end

