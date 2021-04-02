%define modname geoip
Name: issabel-geoip
Version: 1.6.12
Release: 2
Summary: GeoIP

Group: System Environment/Base
License: GPLv2
Url: http://www.issabel.org

Source0: issabel-%{modname}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-root

Source1: geoip_update.sh
Source2: geoip-csv-to-dat.cpp
Source3: 20_convert_dbip
Source4: 20_convert_geolite2
Source5: 20_build_xtables
Source10: GeoIP-initial.dat
Source11: GeoIPv6-initial.dat
Patch0: geoip-kosovo-patch.diff

Obsoletes:      GeoIP < %{version}-%{release}
Provides:       GeoIP = %{version}-%{release}

Requires:       gzip
Requires:       wget
Requires:       issabel-framework

#BuildArch:     noarch

%description
This package contains geoip salsa


%package devel
Summary:        Development headers and libraries for GeoIP
Group:          Development/Libraries
Requires:       %{name} = %{version}-%{release}
Provides:       GeoIP-devel = %{version}-%{release}
Obsoletes:      GeoIP-devel < %{version}-%{release}

%description devel
Development headers and static libraries for building GeoIP-based applications.



%prep

%setup -q -c %{modname}_%{version}
cd issabel-%{modname}_%{version}/geoip-api-c-main
cp %{SOURCE2} .
%patch0 -p0

%build
cd issabel-%{modname}_%{version}/geoip-api-c-main
./bootstrap
%configure --disable-static --disable-dependency-tracking

# Kill bogus rpaths
sed -i -e 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g' \
        -e 's|^runpath_var=LD_RUN_PATH|runpath_var=DIE_RPATH_DIE|g' libtool

make %{?_smp_mflags}


g++ -o geoip-csv-to-dat -L libGeoIP/.libs -lGeoIP geoip-csv-to-dat.cpp


%install

mkdir -p    $RPM_BUILD_ROOT/usr/share/GeoIP/
mkdir -p    $RPM_BUILD_ROOT/usr/share/geoip/
mkdir -p    $RPM_BUILD_ROOT/usr/bin
ls -la
find . -name geoip-csv-to-dat
install -Dpm 755 issabel-%{modname}_%{version}-%{release}/geoip-api-c-main/geoip-csv-to-dat $RPM_BUILD_ROOT/usr/bin
cd issabel-%{modname}_%{version}-%{release}/geoip-api-c-main
#rm -rf $RPM_BUILD_ROOT
make DESTDIR=%{buildroot} install

# nix the stuff we don't need like .la files.
rm -f %{buildroot}%{_libdir}/*.la

install -Dpm 755 %{SOURCE1} $RPM_BUILD_ROOT/etc/cron.daily/geoip_update.sh

install -Dpm 755 %{SOURCE3} %{buildroot}%{_datadir}/geoip/
install -Dpm 755 %{SOURCE4} %{buildroot}%{_datadir}/geoip/
install -Dpm 755 %{SOURCE5} %{buildroot}%{_datadir}/geoip/
install -p -m 644 %{SOURCE10}  %{buildroot}%{_datadir}/GeoIP/
install -p -m 644 %{SOURCE11}  %{buildroot}%{_datadir}/GeoIP/

# make the default GeoIP.dat a symlink to our -initial data file.
ln -sf GeoIP-initial.dat %{buildroot}%{_datadir}/GeoIP/GeoIP.dat
ln -sf GeoIPv6-initial.dat %{buildroot}%{_datadir}/GeoIP/GeoIPv6.dat

%post
echo UPDATING GEOIP DATABASE...
/etc/cron.daily/geoip_update.sh &> /dev/null


%clean
rm -rf $RPM_BUILD_ROOT

%files
# LGPLv2+

#%doc AUTHORS COPYING ChangeLog README TODO LICENSE* fetch-*
%{_bindir}/geoiplookup
%{_bindir}/geoip-csv-to-dat
%{_bindir}/geoiplookup6
%dir %{_datadir}/GeoIP/
%{_datadir}/GeoIP/GeoIP-initial.dat
%{_datadir}/GeoIP/GeoIPv6-initial.dat
# The other databases are %%verify(not md5 size mtime) so that they can be updated via the cron scripts
# and rpm will not moan about the files having changed
%verify(not md5 size link mtime) %{_datadir}/GeoIP/GeoIP.dat
%verify(not md5 size link mtime) %{_datadir}/GeoIP/GeoIPv6.dat
%{_libdir}/libGeoIP.so.1
%{_libdir}/libGeoIP.so.1.*
%{_mandir}/man1/geoiplookup.1*
%{_mandir}/man1/geoiplookup6.1*

%defattr(755, root, root)
/etc/cron.daily/geoip_update.sh
/usr/share/geoip/20_convert_dbip 
/usr/share/geoip/20_convert_geolite2
/usr/share/geoip/20_build_xtables

%files devel
# LGPLv2+
%{_includedir}/GeoIP.h
%{_includedir}/GeoIPCity.h
%{_libdir}/libGeoIP.so
%{_libdir}/pkgconfig/geoip.pc




%changelog

