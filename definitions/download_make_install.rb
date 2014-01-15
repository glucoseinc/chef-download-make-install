EXT_TYPE_CMD = {
  '.tar' => ['tar', 'xf'],
  '.tgz' => ['tar', 'zxf'],
  '.tar.gz' => ['tar', 'zxf'],
  '.tar.bz2' => ['tar', 'jxf'],
  '.zip' => ['unzip', '-o'],
  '.gz' => ['gzip', '-d'],
  '.bz2' => ['bzip2', '-d'],
}
EXT_TYPES = EXT_TYPE_CMD.keys.collect{|k| [k.length, k]}.sort.reverse.collect{|n,k|k}

define :download_make_install, :action => :build, :target => nil, :environment => nil, :install_prefix => '/usr/local', :configure_options => nil, :configure_command => nil, :make_command => nil, :install_command => nil do

  chef_gem "mechanize" do
    # latest mechanize depends on mime-types 2.0
    # but chef requires mime-types ~1.16.
    version "~> 2.6.0"
    action :install
  end

  require 'mechanize'
  agent = Mechanize.new
  agent.pluggable_parser.default = Mechanize::Download

  def make_extract_command(path)
    lpath = path.downcase
    EXT_TYPES.each do |ext|
      if lpath[-ext.length..-1] == ext
        cmd, opt = EXT_TYPE_CMD[ext]
        return [cmd, opt, path].join(' ')
      end
    end
    "tar zxf #{path}"  #fall-back for unknown extension.
  end

  def extract_name(path)
    lpath = path.downcase
    EXT_TYPES.each do |ext|
      if lpath[-ext.length..-1] == ext
        return path[0...-ext.length]
      end
    end
    path[0..-File::extname(path).length]  #fall-back for unknown extension.
  end

  archive_url = params[:name]
  archive_dir = Chef::Config[:file_cache_path]
  archive_file = File::basename(archive_url)
  if node[:download_make_install][:archive_dir]
    archive_url = "#{node[:download_make_install][:archive_dir]}/#{archive_file}"
  end
  if URI.parse(archive_url).scheme =~ /http/
    archive_file = agent.head(archive_url).filename
  end

  environment = params[:environment] or {}
  install_prefix = params[:install_prefix]
  configure_options = params[:configure_options]
  target = params[:target]

  extract_command = make_extract_command(archive_file)
  extract_path = "#{archive_dir}/#{extract_name(archive_file)}"

  case params[:action]
  when :build

    ruby_block "Download #{archive_file}" do
      block do
        Dir.chdir archive_dir do
          agent.get(archive_url).save
        end
      end

      not_if {File.exists?("#{archive_dir}/#{archive_file}") or (target and File.exists?(target))}
    end

    execute "extract #{archive_file}" do
      cwd archive_dir
      command extract_command
      not_if {File.exists?(extract_path) or (target and File.exists?(target))}
    end

    execute "configure #{archive_file}" do
      cwd extract_path
      environment environment
      command (params[:configure_command] or "./configure --prefix=#{install_prefix} #{configure_options}")
      not_if {!File.exists?("#{extract_path}/configure") or File.exists?("#{extract_path}/Makefile") or (target and File.exists?(target))}
    end

    execute "make #{archive_file}" do
      cwd extract_path
      environment environment
      command (params[:build_command] or "make")
      not_if {(target and File.exists?(target))}
    end

    execute "make install #{archive_file}" do
      cwd extract_path
      environment environment
      command (params[:install_command] or "make install")
      not_if {(target and File.exists?(target))}
      notifies :run, "execute[ldconfig #{archive_file}]", :immediately
    end

    execute "ldconfig #{archive_file}" do
      action :nothing
      command "ldconfig"
    end

  end
end
