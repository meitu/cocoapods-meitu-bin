module CBin
  class PodSize
    include Pod

    # 多线程锁
    @@lock = Mutex.new
    # 阈值，单位MB
    @@size_threshold = 500
    # 存放过大Pod信息的临时文件
    @@tmp_file_path = File.join(Dir.pwd, '.mtxx_big_pods.log')

    # 添加超过阈值的pod
    def self.add_pod(pod)
      if pod[:size].to_i < @@size_threshold * 1024
        return
      end
      @@lock.synchronize do
        File.open(@@tmp_file_path, "a") do |f|
          f.write(format_pod_size(pod))
        end
      end
    end

    # 格式化pod
    def self.format_pod_size(pod)
      unit = 'KB'
      size = pod[:size].to_i
      if size >= 1024 * 1024
        unit = 'GB'
        size = ('%.1f' % (size / 1024.0 / 1024.0)).to_f
      elsif size >= 1024
        unit = 'MB'
        size = ('%.1f' % (size / 1024.0)).to_f
      end
      "#{pod[:name]}:#{size}#{unit}\n"
    end

    # 打印超过阈值的Pod库
    def self.print_pods
      unless File.exist?(@@tmp_file_path)
        return
      end
      UI.puts "\n"
      UI.puts "以下Pod库下载大小大于阈值`#{@@size_threshold}MB`:".green
      File.open(@@tmp_file_path, "r") do |f|
        f.readlines.map do |line|
          UI.puts " - #{line.strip}".green
        end
      end
      # 打印完成后，删除临时文件
      FileUtils.rm_f(@@tmp_file_path) if File.exist?(@@tmp_file_path)
    end
  end
end
