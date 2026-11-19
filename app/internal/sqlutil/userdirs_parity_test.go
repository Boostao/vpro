package sqlutil

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestUserDirsCrossLanguageEdgeParity(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX/XDG symlink and HOME edge matrix runs on Unix")
	}

	tmp := t.TempDir()
	realDir := filepath.Join(tmp, "real_vpro")
	symlinkDir := filepath.Join(tmp, "symlink_vpro")
	cwdDir := filepath.Join(tmp, "cwd")
	if err := os.MkdirAll(realDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(cwdDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(realDir, symlinkDir); err != nil {
		t.Fatal(err)
	}

	origWd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(origWd) })
	if err := os.Chdir(cwdDir); err != nil {
		t.Fatal(err)
	}

	// 1. Symlinked VPRO_DATA_DIR / VPRO_CONFIG_DIR preserve lexical symlink path (no realpath dereference)
	t.Setenv("HOME", "/home/x")
	t.Setenv("VPRO_DATA_DIR", symlinkDir)
	t.Setenv("VPRO_CONFIG_DIR", symlinkDir)
	if got, err := UserDataDir(); err != nil || got != symlinkDir {
		t.Fatalf("symlink UserDataDir() = %q, %v; want %q", got, err, symlinkDir)
	}
	if got, err := UserConfigDir(); err != nil || got != symlinkDir {
		t.Fatalf("symlink UserConfigDir() = %q, %v; want %q", got, err, symlinkDir)
	}

	// 2. Tilde overrides (~, ~/, ~/custom_vpro_test, ~/a/b/../c/) expand against HOME; ~other stays relative
	t.Setenv("VPRO_DATA_DIR", "~/custom_vpro_test")
	t.Setenv("VPRO_CONFIG_DIR", "~/a/b/../cfg/")
	if got, err := UserDataDir(); err != nil || got != "/home/x/custom_vpro_test" {
		t.Fatalf("tilde UserDataDir() = %q, %v; want /home/x/custom_vpro_test", got, err)
	}
	if got, err := UserConfigDir(); err != nil || got != "/home/x/a/cfg" {
		t.Fatalf("tilde dotdot UserConfigDir() = %q, %v; want /home/x/a/cfg", got, err)
	}
	t.Setenv("VPRO_DATA_DIR", "~")
	if got, err := UserDataDir(); err != nil || got != "/home/x" {
		t.Fatalf("bare tilde UserDataDir() = %q, %v; want /home/x", got, err)
	}
	t.Setenv("VPRO_DATA_DIR", "~literal")
	if got, err := UserDataDir(); err != nil || got != filepath.Join(cwdDir, "~literal") {
		t.Fatalf("~literal UserDataDir() = %q, %v; want %q", got, err, filepath.Join(cwdDir, "~literal"))
	}

	// 3. Non-existent .. and duplicate/trailing slashes clean lexically
	t.Setenv("VPRO_DATA_DIR", "/a/b/../c/")
	t.Setenv("VPRO_CONFIG_DIR", "/a//c/")
	if got, err := UserDataDir(); err != nil || got != "/a/c" {
		t.Fatalf("dotdot UserDataDir() = %q, %v; want /a/c", got, err)
	}
	if got, err := UserConfigDir(); err != nil || got != "/a/c" {
		t.Fatalf("double-slash UserConfigDir() = %q, %v; want /a/c", got, err)
	}

	// 4. Whitespace segment override preserved
	t.Setenv("VPRO_DATA_DIR", " ")
	t.Setenv("VPRO_CONFIG_DIR", " ")
	wantSpace := cwdDir + "/ "
	if got, err := UserDataDir(); err != nil || got != wantSpace {
		t.Fatalf("space UserDataDir() = %q, %v; want %q", got, err, wantSpace)
	}
	if got, err := UserConfigDir(); err != nil || got != wantSpace {
		t.Fatalf("space UserConfigDir() = %q, %v; want %q", got, err, wantSpace)
	}

	// 5. Relative XDG_DATA_HOME / XDG_CONFIG_HOME ignored per XDG Base Dir Spec
	if runtime.GOOS != "darwin" {
		t.Setenv("VPRO_DATA_DIR", "")
		t.Setenv("VPRO_CONFIG_DIR", "")
		t.Setenv("XDG_DATA_HOME", "rel_xdg_data")
		t.Setenv("XDG_CONFIG_HOME", "rel_xdg_cfg")
		if got, err := UserDataDir(); err != nil || got != "/home/x/.local/share/vpro" {
			t.Fatalf("rel XDG_DATA_HOME UserDataDir() = %q, %v; want /home/x/.local/share/vpro", got, err)
		}
		if got, err := UserConfigDir(); err != nil || got != "/home/x/.config/vpro" {
			t.Fatalf("rel XDG_CONFIG_HOME UserConfigDir() = %q, %v; want /home/x/.config/vpro", got, err)
		}

		// Symlinked absolute XDG_* preserved
		t.Setenv("XDG_DATA_HOME", symlinkDir)
		t.Setenv("XDG_CONFIG_HOME", symlinkDir)
		wantXdgSym := symlinkDir + "/vpro"
		if got, err := UserDataDir(); err != nil || got != wantXdgSym {
			t.Fatalf("symlink XDG_DATA_HOME = %q, %v; want %q", got, err, wantXdgSym)
		}
		if got, err := UserConfigDir(); err != nil || got != wantXdgSym {
			t.Fatalf("symlink XDG_CONFIG_HOME = %q, %v; want %q", got, err, wantXdgSym)
		}

		// Empty HOME="" with valid absolute XDG_* succeeds without requiring HOME
		t.Setenv("HOME", "")
		t.Setenv("XDG_DATA_HOME", "/xdg/d")
		t.Setenv("XDG_CONFIG_HOME", "/xdg/c")
		if got, err := UserDataDir(); err != nil || got != "/xdg/d/vpro" {
			t.Fatalf("empty HOME + abs XDG_DATA_HOME = %q, %v; want /xdg/d/vpro", got, err)
		}
		if got, err := UserConfigDir(); err != nil || got != "/xdg/c/vpro" {
			t.Fatalf("empty HOME + abs XDG_CONFIG_HOME = %q, %v; want /xdg/c/vpro", got, err)
		}
	}

	// 6. Empty HOME="" with unset/relative XDG_* and unset/tilde overrides errors cleanly
	t.Setenv("HOME", "")
	t.Setenv("VPRO_DATA_DIR", "")
	t.Setenv("VPRO_CONFIG_DIR", "")
	t.Setenv("XDG_DATA_HOME", "")
	t.Setenv("XDG_CONFIG_HOME", "")
	if got, err := UserDataDir(); err == nil {
		t.Fatalf("empty HOME UserDataDir() succeeded with %q, want error", got)
	}
	if got, err := UserConfigDir(); err == nil {
		t.Fatalf("empty HOME UserConfigDir() succeeded with %q, want error", got)
	}
	t.Setenv("VPRO_DATA_DIR", "~/vp")
	if got, err := UserDataDir(); err == nil {
		t.Fatalf("empty HOME + tilde UserDataDir() succeeded with %q, want error", got)
	}
}
