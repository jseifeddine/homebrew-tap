require "digest"

class Zsh < Formula
  # Default repository and reference
  DEFAULT_REPO = "https://git.code.sf.net/p/zsh/code".freeze
  DEFAULT_REF = "master".freeze

  # Detect version from Config/version.mk in the zsh source
  def self.detect_version_from_source(repo, ref)
    version_content = nil

    # Try different methods based on the repository host
    case repo
    when /github\.com/
      # For GitHub, use raw content URL
      # Extract owner/repo from URL
      if (match = repo.match(%r{github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$}))
        owner_repo = match[1]
        raw_url = "https://raw.githubusercontent.com/#{owner_repo}/#{ref}/Config/version.mk"
        version_content = `curl -s "#{raw_url}" 2>/dev/null`
      end

    when /gitlab\.com/
      # For GitLab, use raw content URL
      # Extract project path from URL
      if (match = repo.match(%r{gitlab\.com[:/](.+?)(?:\.git)?$}))
        project_path = match[1]
        # GitLab raw URLs use /-/raw/ format
        raw_url = "https://gitlab.com/#{project_path}/-/raw/#{ref}/Config/version.mk"
        version_content = `curl -s "#{raw_url}" 2>/dev/null`
      end

    when /git\.code\.sf\.net/
      # For SourceForge, use their web interface
      web_url = repo.gsub("git.code.sf.net", "sourceforge.net")
      version_content = `curl -s "#{web_url}/ci/#{ref}/tree/Config/version.mk?format=raw" 2>/dev/null`

    else
      # For other Git hosts or self-hosted instances, try git archive first
      version_content = `git archive --remote=#{repo} #{ref} Config/version.mk 2>/dev/null | tar -xO 2>/dev/null`

      # If git archive fails, try a shallow clone as last resort
      if version_content.nil? || version_content.strip.empty?
        Dir.mktmpdir do |tmpdir|
          # Shallow clone with depth 1 to minimize data transfer
          clone_success = system("git clone --depth 1 --branch #{ref} #{repo} #{tmpdir}/zsh-temp >/dev/null 2>&1")
          if clone_success && File.exist?("#{tmpdir}/zsh-temp/Config/version.mk")
            version_content = File.read("#{tmpdir}/zsh-temp/Config/version.mk")
          end
        end
      end
    end

    # Parse version from content
    if version_content && !version_content.strip.empty?
      # Parse VERSION=x.x.x.x-test line from version.mk
      version_line = version_content.lines.find { |line| line.strip.start_with?("VERSION=") }
      if version_line
        version = version_line.strip.split("=", 2)[1]
        return version if version.present?
      end
    end

    nil
  rescue => e
    # Log error for debugging but don't fail
    warn "Version detection failed: #{e.message}" if ENV["HOMEBREW_DEBUG"]
    nil
  end

  # Parse installation arguments for custom repo, ref, and version
  def self.parse_args
    repo = ENV["HOMEBREW_ZSH_REPO"] || DEFAULT_REPO
    ref = ENV["HOMEBREW_ZSH_REF"] || DEFAULT_REF

    # Auto-detect version from source unless overridden
    version = ENV["HOMEBREW_ZSH_VERSION_OVERRIDE"].presence || detect_version_from_source(repo, ref) || "5.9"

    [repo, ref, version]
  end

  # Check if ref is a commit hash (40 character hex string)
  def self.commit_hash?(ref)
    ref.match?(/\A[a-f0-9]{40}\z/)
  end

  # Get remote commit hash for a branch
  def self.remote_commit_hash(repo, ref)
    return if commit_hash?(ref)

    `git ls-remote #{repo} #{ref}`.split.first
  rescue
    nil
  end

  repo, ref, version_override = parse_args

  # Homebrew formula DSL - components must be in specific order
  desc "UNIX shell (command interpreter)"
  homepage "https://www.zsh.org/"

  # Use a unique download name based on the repository to avoid cache conflicts
  # This ensures different repos don't share the same cached directory
  repo_hash = Digest::SHA256.hexdigest(repo)[0..7]
  url repo, using: :git, branch: ref, download_name: "zsh-#{repo_hash}"

  # Calculate and set version with commit hash if needed
  # version_override is guaranteed to be non-empty from parse_args (defaults to "5.9")
  if commit_hash?(ref)
    version "#{version_override}-#{ref[0..7]}"
  else
    remote_hash = remote_commit_hash(repo, ref)
    if remote_hash
      version "#{version_override}-#{remote_hash[0..7]}"
    else
      version version_override
    end
  end

  license "MIT-Modern-Variant"

  depends_on "autoconf" => :build
  depends_on "ncurses"
  depends_on "pcre2"

  on_system :linux, macos: :ventura_or_newer do
    depends_on "texinfo" => :build
  end

  # Override version to show more detailed information including git ref
  def version_scheme
    0
  end

  def detailed_version_info
    return @detailed_version_info if defined?(@detailed_version_info)

    repo, ref, version_override = self.class.parse_args
    @detailed_version_info = "#{version_override} (from #{repo.split("/").last(2).join("/")} @ #{ref})"
  end

  # Store commit information for upgrade tracking
  def store_commit_info
    repo, ref, version_override = self.class.parse_args

    # Get the actual commit hash that was checked out
    actual_commit = `git rev-parse HEAD`.strip

    if actual_commit.present?
      # Store commit info in a file for upgrade comparisons
      commit_info_file = prefix/"COMMIT_INFO"
      commit_info_file.write <<~INFO
        REPO=#{repo}
        REF=#{ref}
        VERSION=#{version_override}
        COMMIT=#{actual_commit}
        INSTALLED_AT=#{Time.now.iso8601}
        IS_COMMIT_REF=#{self.class.commit_hash?(ref)}
      INFO
    end
  end

  # Custom upgrade logic
  def outdated?
    return false unless (prefix/"COMMIT_INFO").exist?

    commit_info = {}
    (prefix/"COMMIT_INFO").read.each_line do |line|
      key, value = line.strip.split("=", 2)
      commit_info[key] = value
    end

    # If installed from a specific commit hash, never outdated
    return false if commit_info["IS_COMMIT_REF"] == "true"

    # For branch refs, check if remote has new commits
    repo = commit_info["REPO"]
    ref = commit_info["REF"]
    installed_commit = commit_info["COMMIT"]

    return false if repo.nil? || ref.nil? || installed_commit.nil?

    remote_commit = self.class.remote_commit_hash(repo, ref)
    return false unless remote_commit

    # Outdated if remote commit is different from installed commit
    remote_commit != installed_commit
  rescue
    false
  end

  def install
    # Fix compile with newer Clang
    # https://www.zsh.org/mla/workers/2020/index.html
    # https://github.com/Homebrew/homebrew-core/issues/64921
    ENV.append_to_cflags "-Wno-implicit-function-declaration" if DevelopmentTools.clang_build_version >= 1200

    system "Util/preconfig"

    system "./configure", "--prefix=#{prefix}",
           "--enable-fndir=#{pkgshare}/functions",
           "--enable-scriptdir=#{pkgshare}/scripts",
           "--enable-site-fndir=#{HOMEBREW_PREFIX}/share/zsh/site-functions",
           "--enable-site-scriptdir=#{HOMEBREW_PREFIX}/share/zsh/site-scripts",
           "--enable-runhelpdir=#{pkgshare}/help",
           "--enable-cap",
           "--enable-maildir-support",
           "--enable-multibyte",
           "--enable-pcre",
           "--enable-zsh-secure-free",
           "--enable-unicode9",
           "--enable-etcdir=/etc",
           "--with-tcsetpgrp",
           "DL_EXT=bundle"

    # Do not version installation directories.
    inreplace ["Makefile", "Src/Makefile"],
              "$(libdir)/$(tzsh)/$(VERSION)", "$(libdir)"

    # disable target install.man, because the required yodl comes neither with macOS nor Homebrew
    # also disable install.runhelp and install.info because they would also fail or have no effect
    system "make", "install.bin", "install.modules", "install.fns"

    # Store commit information for upgrade tracking
    store_commit_info
  end

  def caveats
    # Try to read actual build info from installed version
    if (commit_info_file = prefix/"COMMIT_INFO").exist?
      commit_info = {}
      commit_info_file.read.each_line do |line|
        key, value = line.strip.split("=", 2)
        commit_info[key] = value if key && value
      end

      repo = commit_info["REPO"] || self.class::DEFAULT_REPO
      ref = commit_info["REF"] || self.class::DEFAULT_REF
      version_override = commit_info["VERSION"] || "5.9"
    else
      # Fallback to parsing from environment (for pre-install display)
      repo, ref, version_override = self.class.parse_args
    end

    <<~EOS
      Build information:
        Repository: #{repo}
        Reference:  #{ref}
        Version:    #{version_override}

        This zsh build was compiled from source using the above repository and git
        reference. The binary includes all modern features and custom optimizations.
    EOS
  end

  test do
    assert_equal "homebrew", shell_output("#{bin}/zsh -c 'echo homebrew'").chomp
    system bin/"zsh", "-c", "printf -v hello -- '%s'"
    system bin/"zsh", "-c", "zmodload zsh/pcre"
  end
end
