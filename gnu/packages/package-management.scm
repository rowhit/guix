;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013, 2014, 2015 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2015 Ricardo Wurmus <rekado@elephly.net>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages package-management)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system python)
  #:use-module ((guix licenses) #:select (gpl2+ gpl3+ lgpl2.1+ asl2.0))
  #:use-module (gnu packages)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages file)
  #:use-module (gnu packages backup)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages graphviz)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages autotools)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages nettle)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages web)
  #:use-module (gnu packages man)
  #:use-module (gnu packages emacs)
  #:use-module (gnu packages bdw-gc)
  #:use-module (gnu packages python)
  #:use-module (gnu packages popt)
  #:use-module (gnu packages gnuzilla)
  #:use-module (gnu packages cpio)
  #:use-module (gnu packages tls))

(define (boot-guile-uri arch)
  "Return the URI for the bootstrap Guile tarball for ARCH."
  (if (string=? "armhf" arch)
      (string-append "http://alpha.gnu.org/gnu/guix/bootstrap/"
                     arch "-linux"
                     "/20150101/guile-2.0.11.tar.xz")
      (string-append "http://alpha.gnu.org/gnu/guix/bootstrap/"
                     arch "-linux"
                     "/20131110/guile-2.0.9.tar.xz")))

(define-public guix-0.9.0
  (package
    (name "guix")
    (version "0.9.0")
    (source (origin
             (method url-fetch)
             (uri (string-append "ftp://alpha.gnu.org/gnu/guix/guix-"
                                 version ".tar.gz"))
             (sha256
              (base32
               "0h573z2br0bf43sxyzia9xlm03n3y43zg1snds3c2piq2m6kabrn"))))
    (build-system gnu-build-system)
    (arguments
     `(#:configure-flags (list
                          "--localstatedir=/var"
                          "--sysconfdir=/etc"
                          (string-append "--with-bash-completion-dir="
                                         (assoc-ref %outputs "out")
                                         "/etc/bash_completion.d")
                          (string-append "--with-libgcrypt-prefix="
                                         (assoc-ref %build-inputs
                                                    "libgcrypt")))
       #:parallel-tests? #f           ;work around <http://bugs.gnu.org/21097>
       #:phases (modify-phases %standard-phases
                  (add-before
                   'configure 'copy-bootstrap-guile
                   (lambda* (#:key system inputs #:allow-other-keys)
                     (define (boot-guile-version arch)
                       (if (string=? "armhf" arch)
                           "2.0.11"
                           "2.0.9"))

                     (define (copy arch)
                       (let ((guile  (assoc-ref inputs
                                                (string-append "boot-guile/"
                                                               arch)))
                             (target (string-append "gnu/packages/bootstrap/"
                                                    arch "-linux/"
                                                    "/guile-"
                                                    (boot-guile-version arch)
                                                    ".tar.xz")))
                         (copy-file guile target)))

                     (copy "i686")
                     (copy "x86_64")
                     (copy "mips64el")
                     (copy "armhf")
                     #t))
                  (add-after
                   'unpack 'disable-container-tests
                   ;; XXX FIXME: These tests fail within the build container.
                   (lambda _
                     (substitute* "tests/syscalls.scm"
                       (("^\\(test-assert \"(clone|setns|pivot-root)\"" all)
                        (string-append "(test-skip 1)\n" all)))
                     (substitute* "tests/containers.scm"
                       (("^\\(test-assert" all)
                        (string-append "(test-skip 1)\n" all)))
                     (when (file-exists? "tests/guix-environment-container.sh")
                       (substitute* "tests/guix-environment-container.sh"
                         (("guix environment --version")
                          "exit 77\n")))
                     #t))
                  (add-before 'check 'set-SHELL
                    (lambda _
                      ;; 'guix environment' tests rely on 'SHELL' having a
                      ;; correct value, so set it.
                      (setenv "SHELL" (which "sh"))
                      #t))
                  (add-after
                   'install 'wrap-program
                   (lambda* (#:key inputs outputs #:allow-other-keys)
                     ;; Make sure the 'guix' command finds GnuTLS and
                     ;; Guile-JSON automatically.
                     (let* ((out    (assoc-ref outputs "out"))
                            (json   (assoc-ref inputs "guile-json"))
                            (gnutls (assoc-ref inputs "gnutls"))
                            (path   (string-append
                                     json "/share/guile/site/2.0:"
                                     gnutls "/share/guile/site/2.0")))
                       (wrap-program (string-append out "/bin/guix")
                         `("GUILE_LOAD_PATH" ":" prefix (,path))
                         `("GUILE_LOAD_COMPILED_PATH" ":" prefix (,path)))
                       #t))))))
    (native-inputs `(("pkg-config" ,pkg-config)
                     ("emacs" ,emacs-no-x)))      ;for guix.el
    (inputs
     (let ((boot-guile (lambda (arch hash)
                         (origin
                          (method url-fetch)
                          (uri (boot-guile-uri arch))
                          (sha256 hash)))))
       `(("bzip2" ,bzip2)
         ("gzip" ,gzip)

         ("sqlite" ,sqlite)
         ("libgcrypt" ,libgcrypt)
         ("guile" ,guile-2.0)

         ("boot-guile/i686"
          ,(boot-guile "i686"
                       (base32
                        "0im800m30abgh7msh331pcbjvb4n02smz5cfzf1srv0kpx3csmxp")))
         ("boot-guile/x86_64"
          ,(boot-guile "x86_64"
                       (base32
                        "1w2p5zyrglzzniqgvyn1b55vprfzhgk8vzbzkkbdgl5248si0yq3")))
         ("boot-guile/mips64el"
          ,(boot-guile "mips64el"
                       (base32
                        "0fzp93lvi0hn54acc0fpvhc7bvl0yc853k62l958cihk03q80ilr")))
         ("boot-guile/armhf"
          ,(boot-guile "armhf"
                       (base32
                        "1mi3brl7l58aww34rawhvja84xc7l1b4hmwdmc36fp9q9mfx0lg5"))))))
    (propagated-inputs
     `(("gnutls" ,gnutls)                         ;for 'guix download' & co.
       ("guile-json" ,guile-json)
       ("geiser" ,geiser)))                       ;for guix.el

    (home-page "http://www.gnu.org/software/guix")
    (synopsis "Functional package manager for installed software packages and versions")
    (description
     "GNU Guix is a functional package manager for the GNU system, and is
also a distribution thereof.  It includes a virtual machine image.  Besides
the usual package management features, it also supports transactional
upgrades and roll-backs, per-user profiles, and much more.  It is based on
the Nix package manager.")
    (license gpl3+)))

(define guix-devel
  ;; Development version of Guix.
  ;;
  ;; Note: use a short commit id; when using the long one, the limit on socket
  ;; file names is exceeded while running the tests.
  (let ((commit "5c36edc"))
    (package (inherit guix-0.9.0)
      (version (string-append "0.9.0." commit))
      (source (origin
                (method git-fetch)
                (uri (git-reference
                      (url "git://git.sv.gnu.org/guix.git")
                      (commit commit)))
                (sha256
                 (base32
                  "008fv3yj1jkxxma9vp8wzmkk3m82kgchaj9y7lpcvkqzcdhz8h7p"))
                (file-name (string-append "guix-" version "-checkout"))))
      (arguments
       (substitute-keyword-arguments (package-arguments guix-0.9.0)
         ((#:configure-flags flags)
          ;; Set 'DOT_USER_PROGRAM' to the empty string so we don't keep a
          ;; reference to Graphviz, whose closure is pretty big (too big for
          ;; the GuixSD installation image.)
          `(cons "ac_cv_path_DOT_USER_PROGRAM=dot" ,flags))
         ((#:phases phases)
          `(modify-phases ,phases
             (add-after
              'unpack 'bootstrap
              (lambda _
                ;; Make sure 'msgmerge' can modify the PO files.
                (for-each (lambda (po)
                            (chmod po #o666))
                          (find-files "." "\\.po$"))

                (zero? (system* "sh" "bootstrap"))))))))
      (native-inputs
       `(("autoconf" ,(autoconf-wrapper))
         ("automake" ,automake)
         ("gettext" ,gnu-gettext)
         ("texinfo" ,texinfo)
         ("graphviz" ,graphviz)
         ("help2man" ,help2man)
         ,@(package-native-inputs guix-0.9.0))))))

(define-public guix guix-devel)

(define-public nix
  (package
    (name "nix")
    (version "1.10")
    (source (origin
             (method url-fetch)
             (uri (string-append "http://nixos.org/releases/nix/nix-"
                                 version "/nix-" version ".tar.xz"))
             (sha256
              (base32
               "1xhh7l1dqwn6i3m51xp8l0aa95da3823w4h8n8hfxlcxaixcl4jn"))))
    (build-system gnu-build-system)
    ;; XXX: Should we pass '--with-store-dir=/gnu/store'?  But then we'd also
    ;; need '--localstatedir=/var'.  But then!  The thing would use /var/nix
    ;; instead of /var/guix.  So in the end, we do nothing special.
    (arguments
     '(#:configure-flags
       ;; Set the prefixes of Perl libraries to avoid propagation.
       (let ((perl-libdir (lambda (p)
                            (string-append
                             (assoc-ref %build-inputs p)
                             "/lib/perl5/site_perl"))))
         (list (string-append "--with-dbi="
                              (perl-libdir "perl-dbi"))
               (string-append "--with-dbd-sqlite="
                              (perl-libdir "perl-dbd-sqlite"))
               (string-append "--with-www-curl="
                              (perl-libdir "perl-www-curl"))))))
    (native-inputs `(("perl" ,perl)
                     ("pkg-config" ,pkg-config)))
    (inputs `(("curl" ,curl)
              ("openssl" ,openssl)
              ("libgc" ,libgc)
              ("sqlite" ,sqlite)
              ("bzip2" ,bzip2)
              ("perl-www-curl" ,perl-www-curl)
              ("perl-dbi" ,perl-dbi)
              ("perl-dbd-sqlite" ,perl-dbd-sqlite)))
    (home-page "http://nixos.org/nix/")
    (synopsis "The Nix package manager")
    (description
     "Nix is a purely functional package manager.  This means that it treats
packages like values in purely functional programming languages such as
Haskell—they are built by functions that don't have side-effects, and they
never change after they have been built.  Nix stores packages in the Nix
store, usually the directory /nix/store, where each package has its own unique
sub-directory.")
    (license lgpl2.1+)))

(define-public stow
  (package
    (name "stow")
    (version "2.2.2")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://gnu/stow/stow-"
                                  version ".tar.gz"))
              (sha256
               (base32
                "1pvky9fayms4r6fhns8jd0vavszd7d979w62vfd5n88v614pdxz2"))))
    (build-system gnu-build-system)
    (inputs
     `(("perl" ,perl)))
    (native-inputs
     `(("perl-test-simple" ,perl-test-simple)
       ("perl-test-output" ,perl-test-output)
       ("perl-capture-tiny" ,perl-capture-tiny)
       ("perl-io-stringy" ,perl-io-stringy)))
    (home-page "https://www.gnu.org/software/stow/")
    (synopsis "Managing installed software packages")
    (description
     "GNU Stow is a symlink manager.  It generates symlinks to directories
of data and makes them appear to be merged into the same directory.  It is
typically used for managing software packages installed from source, by
letting you install them apart in distinct directories and then create
symlinks to the files in a common directory such as /usr/local.")
    (license gpl2+)))

(define-public rpm
  (package
    (name "rpm")
    (version "4.12.0")
    (source (origin
              (method url-fetch)
              (uri (string-append "http://rpm.org/releases/rpm-4.12.x/rpm-"
                                  version ".tar.bz2"))
              (sha256
               (base32
                "18hk47hc755nslvb7xkq4jb095z7va0nlcyxdpxayc4lmb8mq3bp"))))
    (build-system gnu-build-system)
    (arguments
     '(#:configure-flags '("--with-external-db"   ;use the system's bdb
                           "--enable-python"
                           "--without-lua")
       #:phases (modify-phases %standard-phases
                  (add-before 'configure 'set-nspr-search-path
                    (lambda* (#:key inputs #:allow-other-keys)
                      ;; nspr.pc contains the right -I flag pointing to
                      ;; 'include/nspr', but unfortunately 'configure' doesn't
                      ;; use 'pkg-config'.  Thus, augment CPATH.
                      ;; Likewise for NSS.
                      (let ((nspr (assoc-ref inputs "nspr"))
                            (nss  (assoc-ref inputs "nss")))
                        (setenv "CPATH"
                                (string-append (getenv "CPATH") ":"
                                               nspr "/include/nspr:"
                                               nss "/include/nss"))
                        (setenv "LIBRARY_PATH"
                                (string-append (getenv "LIBRARY_PATH") ":"
                                               nss "/lib/nss"))
                        #t)))
                  (add-after 'install 'fix-rpm-symlinks
                    (lambda* (#:key outputs #:allow-other-keys)
                      ;; 'make install' gets these symlinks wrong.  Fix them.
                      (let* ((out (assoc-ref outputs "out"))
                             (bin (string-append out "/bin")))
                        (with-directory-excursion bin
                          (for-each (lambda (file)
                                      (delete-file file)
                                      (symlink "rpm" file))
                                    '("rpmquery" "rpmverify"))
                          #t)))))))
    (native-inputs
     `(("pkg-config" ,pkg-config)))
    (inputs
     `(("python" ,python-2)
       ("xz" ,xz)
       ("bdb" ,bdb)
       ("popt" ,popt)
       ("nss" ,nss)
       ("nspr" ,nspr)
       ("libarchive" ,libarchive)
       ("nettle" ,nettle)            ;XXX: actually a dependency of libarchive
       ("file" ,file)
       ("bzip2" ,bzip2)
       ("zlib" ,zlib)
       ("cpio" ,cpio)))
    (home-page "http://www.rpm.org/")
    (synopsis "The RPM Package Manager")
    (description
     "The RPM Package Manager (RPM) is a command-line driven package
management system capable of installing, uninstalling, verifying, querying,
and updating computer software packages.  Each software package consists of an
archive of files along with information about the package like its version, a
description.  There is also a library permitting developers to manage such
transactions from C or Python.")

    ;; The whole is GPLv2+; librpm itself is dual-licensed LGPLv2+ | GPLv2+.
    (license gpl2+)))

(define-public diffoscope
  (package
    (name "diffoscope")
    (version "34")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url
                     "https://anonscm.debian.org/cgit/reproducible/diffoscope.git")
                    (commit version)))
              (sha256
               (base32
                "1g8b7bpkmns0355gkr3a244affwx4xzqwahwsl6ivw4z0qv7dih8"))
              (file-name (string-append name "-" version "-checkout"))))
    (build-system python-build-system)
    (arguments
     `(#:python ,python-2
       #:phases (modify-phases %standard-phases
                  (add-before 'build 'disable-egg-zipping
                    (lambda _
                      ;; Leave the .egg file uncompressed.
                      (let ((port (open-file "setup.cfg" "a")))
                        (display "\n[easy_install]\nzip_ok = 0\n"
                                 port)
                        (close-port port)
                        #t)))
                  (add-before 'build 'dependency-on-rpm
                    (lambda _
                      (substitute* "setup.py"
                        ;; Somehow this requirement is reported as not met,
                        ;; even though rpm.py is in the search path.  So
                        ;; delete it.
                        (("'rpm-python',") ""))
                      #t)))
       ;; FIXME: Some obscure test failures.
       #:tests? #f))
    (inputs `(("rpm" ,rpm)                        ;for rpm-python
              ("python-file" ,python2-file)
              ("python-debian" ,python2-debian)
              ("python-libarchive-c" ,python2-libarchive-c)
              ("python-tlsh" ,python2-tlsh)

              ;; Below are modules used for tests.
              ("python-pytest" ,python2-pytest)
              ("python-chardet" ,python2-chardet)))
    (native-inputs `(("python-setuptools" ,python2-setuptools)))
    (home-page "http://diffoscope.org/")
    (synopsis "Compare files, archives, and directories in depth")
    (description
     "Diffoscope tries to get to the bottom of what makes files or directories
different.  It recursively unpacks archives of many kinds and transforms
various binary formats into more human readable forms to compare them.  It can
compare two tarballs, ISO images, or PDFs just as easily.")
    (license gpl3+)))
