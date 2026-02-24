/****************************************************************************************
PCA Making for KRE_Equirty

Disusun oleh: Atha 
Tujuan: Analisis #1
****************************************************************************************/

version 17
clear all
set more off
set linesize 255
set maxvar 32767

/****************************************************************************************
A. PATHS
****************************************************************************************/
global spbun_csv "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Realisasi SPBUN 2024-2025(2024).csv"
global kel_latlon "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/kelurahan_lat_long.csv"

global podes_main    "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Podes/podes2024_desa_02..dta"
global podes_pesisir "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Podes/Podes kab kota pesisir laut.dta"

global outdir "/Users/athamawardi/Desktop/Research-Projects/PSE_Pertamina/Output/probabilistic"
cap mkdir "$outdir"

cap log close
log using "$outdir/run_spbun_podes_susenas.log", replace text

/****************************************************************************************
B. PACKAGES
****************************************************************************************/
cap which reghdfe
if _rc ssc install reghdfe, replace
cap which ftools
if _rc ssc install ftools, replace
cap which geodist
if _rc ssc install geodist, replace
cap which gtools
if _rc ssc install gtools, replace

/****************************************************************************************
C. HELPERS
****************************************************************************************/
capture program drop _std_iddesa10
program define _std_iddesa10
    syntax varname
    capture confirm numeric variable `varlist'
    if !_rc tostring `varlist', replace format("%010.0f")
    replace `varlist' = trim(`varlist')
    replace `varlist' = subinstr(`varlist'," ","",.)
    replace `varlist' = subinstr(`varlist',".","",.)
    replace `varlist' = subinstr(`varlist',",","",.)
    replace `varlist' = substr("0000000000"+`varlist', strlen("0000000000"+`varlist')-9, 10)
    assert strlen(`varlist')==10
end

/****************************************************************************************
D. BUILD "$outdir/podes_vill.dta"  (MAIN + PESISIR + coords fallback)
****************************************************************************************/
tempfile MAIN PES kelcoords

* D1) MAIN
use "$podes_main", clear

cap confirm variable IDDESA
if _rc {
    cap confirm variable iddesa
    if !_rc rename iddesa IDDESA
    cap confirm variable IdDesa
    if !_rc rename IdDesa IDDESA
    cap confirm variable Iddesa
    if !_rc rename Iddesa IDDESA
}
cap confirm variable IDDESA
if _rc {
    di as err "MAIN: cannot find village id variable (IDDESA/iddesa)."
    describe, short
    exit 111
}

cap confirm numeric variable IDDESA
if !_rc tostring IDDESA, replace format("%010.0f")

replace IDDESA = trim(IDDESA)
replace IDDESA = subinstr(IDDESA," ","",.)
replace IDDESA = subinstr(IDDESA,".","",.)
replace IDDESA = subinstr(IDDESA,",","",.)
replace IDDESA = substr("0000000000"+IDDESA, strlen("0000000000"+IDDESA)-9, 10)
assert strlen(IDDESA)==10

rename *, lower
cap confirm variable iddesa
if _rc rename iddesa iddesa
rename iddesa iddesa
_std_iddesa10 iddesa

duplicates drop iddesa, force
save `MAIN', replace

* D2) PESISIR (prefix p_)
use "$podes_pesisir", clear
rename *, lower

cap confirm variable iddesa
if _rc {
    di as err "PESISIR: iddesa not found."
    describe, short
    exit 111
}
_std_iddesa10 iddesa

keep iddesa r307b_lat r307b_long ///
     r308* r309* r310 ///
     r402* r403* ///
     r501* r502* r503* ///
     r507* r508* r509* ///
     r510* r511* r514* r515*

duplicates drop iddesa, force

ds iddesa, not
local pesvars `r(varlist)'
foreach v of local pesvars {
    rename `v' p_`v'
}
save `PES', replace

* D3) MERGE MAIN + PESISIR; fill missing from p_*
use `MAIN', clear
merge 1:1 iddesa using `PES', nogen keep(master match)

capture ds p_*
if !_rc {
    local plist `r(varlist)'
    foreach pv of local plist {
        local tv = substr("`pv'",3,.)
        capture confirm variable `tv'
        if _rc {
            rename `pv' `tv'
        }
        else {
            capture confirm numeric variable `tv'
            if !_rc {
                replace `tv' = `pv' if missing(`tv') & !missing(`pv')
            }
            else {
                capture confirm string variable `tv'
                if !_rc {
                    replace `tv' = `pv' if (`tv'=="") & (`pv'!="")
                }
            }
            drop `pv'
        }
    }
}

* admin codes from iddesa
capture drop r101 r102 r103 r104
gen int r101 = real(substr(iddesa,1,2))
gen int r102 = real(substr(iddesa,3,2))
gen int r103 = real(substr(iddesa,5,3))
gen int r104 = real(substr(iddesa,8,3))

capture drop kab
egen long kab = group(r101 r102), label

* coords prefer r307b_lat/long
cap confirm variable lat_v
if _rc gen double lat_v = .
cap confirm variable lon_v
if _rc gen double lon_v = .

cap confirm variable r307b_lat
if !_rc {
    cap confirm numeric variable r307b_lat
    if _rc destring r307b_lat, replace ignore(",")
    replace lat_v = r307b_lat if missing(lat_v) & !missing(r307b_lat)
}
cap confirm variable r307b_long
if !_rc {
    cap confirm numeric variable r307b_long
    if _rc destring r307b_long, replace ignore(",")
    replace lon_v = r307b_long if missing(lon_v) & !missing(r307b_long)
}
capture drop r307b_lat r307b_long

* fallback coords from kel_latlon if still missing
count if missing(lat_v) | missing(lon_v)
if r(N) > 0 {
    di as txt "Coords missing for " r(N) " villages -> fallback merge from kel_latlon..."
    preserve
        import delimited "$kel_latlon", clear varnames(1) case(preserve) stringcols(_all)

        local idv ""
        local latc ""
        local lonc ""
        foreach v of varlist _all {
            if "`idv'"==""  & strpos(lower("`v'"),"iddesa") local idv `v'
            if "`latc'"=="" & strpos(lower("`v'"),"lat")    local latc `v'
            if "`lonc'"=="" & (strpos(lower("`v'"),"lon") | strpos(lower("`v'"),"long")) local lonc `v'
        }

        if "`idv'"!="" & "`latc'"!="" & "`lonc'"!="" {
            rename `idv' iddesa
            rename `latc' lat_v2
            rename `lonc' lon_v2
            _std_iddesa10 iddesa
            destring lat_v2 lon_v2, replace ignore(",")
            keep iddesa lat_v2 lon_v2
            duplicates drop iddesa, force
            save `kelcoords', replace
        }
    restore

    capture confirm file "`kelcoords'"
    if !_rc {
        merge 1:1 iddesa using `kelcoords', nogen keep(master match)
        replace lat_v = lat_v2 if missing(lat_v) & !missing(lat_v2)
        replace lon_v = lon_v2 if missing(lon_v) & !missing(lon_v2)
        drop lat_v2 lon_v2
    }
}

save "$outdir/podes_vill.dta", replace
di as result "Saved: $outdir/podes_vill.dta"



/****************************************************************************************
G. PODES ONLY: PCA-ready categorical/ordinal outcome construction
****************************************************************************************/

* --------------------------------------------------------------------------------------
* 0) SPBUN-target label (full sample; no filtering)
* --------------------------------------------------------------------------------------
cap drop spbun_target
gen byte spbun_target = 0
foreach v in r308b1a r308b1b r308b1c {
    cap confirm numeric variable `v'
    if !_rc replace spbun_target = 1 if `v'==1
}
label define spbun_target_lbl 0 "Non-target" 1 "Target (tangkap/budidaya/garam)", replace
label values spbun_target spbun_target_lbl

* --------------------------------------------------------------------------------------
* 1) Helpers
* --------------------------------------------------------------------------------------

* Convert 1/2 yes-no variables to 1/0 
capture program drop _yn12_to01
program define _yn12_to01
    syntax varlist
    foreach v of varlist `varlist' {
        cap confirm numeric variable `v'
        if _rc continue
        quietly summarize `v' if !missing(`v'), meanonly
        if (r(min)>=1 & r(max)<=2) {
            replace `v' = (`v'==1) if inlist(`v',1,2)
        }
    }
end

* Bin a numeric variable into 0 + quantiles among non-zero (ordinal 0..4)
capture program drop _bin0q4
program define _bin0q4
    syntax varname(numeric), gen(name)
    tempvar q
    cap drop `gen'
    gen byte `gen' = .
    replace `gen' = 0 if `varlist'==0 & !missing(`varlist')

    quietly count if `varlist'>0 & !missing(`varlist')
    if (r(N)>=30) {
        xtile `q' = `varlist' if `varlist'>0 & !missing(`varlist'), nq(4)
        replace `gen' = `q' if `varlist'>0 & !missing(`varlist')
        label define `gen'_lbl 0 "0" 1 "Q1" 2 "Q2" 3 "Q3" 4 "Q4", replace
    }
    else if (r(N)>0) {
        xtile `q' = `varlist' if `varlist'>0 & !missing(`varlist'), nq(2)
        replace `gen' = cond(`q'==1,1,4) if `varlist'>0 & !missing(`varlist')
        label define `gen'_lbl 0 "0" 1 "Low" 4 "High", replace
    }
    else {
        label define `gen'_lbl 0 "0", replace
    }

    label values `gen' `gen'_lbl
end

* --------------------------------------------------------------------------------------
* 2) Wbasic: basic facilities (categorical/ordinal inputs)
* --------------------------------------------------------------------------------------

cap drop hh_light_total sh_elec elec_cat
egen double hh_light_total = rowtotal(r501a1 r501a2 r501b r501c)
replace hh_light_total = . if missing(r501a1) & missing(r501a2) & missing(r501b) & missing(r501c)

gen double sh_elec = (r501a1 + r501a2) / hh_light_total if hh_light_total>0

gen byte elec_cat = .
replace elec_cat = 3 if sh_elec>=0.90 & sh_elec<=1
replace elec_cat = 2 if sh_elec>=0.50 & sh_elec<0.90
replace elec_cat = 1 if sh_elec>0    & sh_elec<0.50
replace elec_cat = 0 if sh_elec==0

label define elec_cat_lbl 0 "0%" 1 "1-49%" 2 "50-89%" 3 ">=90%", replace
label values elec_cat elec_cat_lbl

cap drop cook_market
cap confirm numeric variable r503b
if !_rc gen byte cook_market = inlist(r503b,1,2,3,4,5,7) if !missing(r503b)

_yn12_to01 r503a1-r503a11
_yn12_to01 r502a r502b r502c

local Wbasic_in "elec_cat r502a r502b r502c cook_market r503a1-r503a11"


* --------------------------------------------------------------------------------------
* 3) Util: utilities / infra
* --------------------------------------------------------------------------------------

_yn12_to01 r507* r508a r508b r509a r509b r510*

foreach v in r509c1 r509c2 r509c3 {
    cap confirm numeric variable `v'
    if !_rc _bin0q4 `v', gen(`v'_b)
}

ds r511c* r514* r515*, has(type numeric)
local util_extra "`r(varlist)'"

foreach v of local util_extra {
    quietly summarize `v' if !missing(`v'), meanonly
    if (r(min)>=1 & r(max)<=2) {
        replace `v' = (`v'==1) if inlist(`v',1,2)
    }
    else if (r(max)>20) {
        _bin0q4 `v', gen(`v'_b)
    }
}

local Wutil_in "r507* r508a r508b r509a r509b"
foreach v in r509c1 r509c2 r509c3 {
    cap confirm variable `v'_b
    if !_rc local Wutil_in "`Wutil_in' `v'_b"
}
foreach v of local util_extra {
    cap confirm variable `v'_b
    if !_rc local Wutil_in "`Wutil_in' `v'_b"
    else local Wutil_in "`Wutil_in' `v'"
}

* --------------------------------------------------------------------------------------
* 4) Edu: education
* --------------------------------------------------------------------------------------
ds r701*, has(type numeric)
local edu_raw "`r(varlist)'"
local Edu_in ""

foreach v of local edu_raw {
    quietly summarize `v' if !missing(`v'), meanonly
    if (r(min)>=1 & r(max)<=2) {
        replace `v' = (`v'==1) if inlist(`v',1,2)
        local Edu_in "`Edu_in' `v'"
    }
    else if (r(max)>20) {
        _bin0q4 `v', gen(`v'_b)
        local Edu_in "`Edu_in' `v'_b"
    }
    else {
        local Edu_in "`Edu_in' `v'"
    }
}

* --------------------------------------------------------------------------------------
* 5) Hlth: health
* --------------------------------------------------------------------------------------
ds r711*, has(type numeric)
local hlth_raw "`r(varlist)'"
local Hlth_in ""

foreach v of local hlth_raw {
    quietly summarize `v' if !missing(`v'), meanonly
    if (r(min)>=1 & r(max)<=2) {
        replace `v' = (`v'==1) if inlist(`v',1,2)
        local Hlth_in "`Hlth_in' `v'"
    }
    else if (r(max)>20) {
        _bin0q4 `v', gen(`v'_b)
        local Hlth_in "`Hlth_in' `v'_b"
    }
    else {
        cap drop ln1p_`v'
        gen double ln1p_`v' = ln(1+`v') if !missing(`v')
        _bin0q4 ln1p_`v', gen(`v'_b)
        local Hlth_in "`Hlth_in' `v'_b"
    }
}

* --------------------------------------------------------------------------------------
* 6) Poverty proxy (keep separate)
* --------------------------------------------------------------------------------------
cap drop lnpov
cap confirm numeric variable r710
if !_rc {
    gen double lnpov = ln(1+r710) if !missing(r710)
    cap drop lnpov_b
    _bin0q4 lnpov, gen(lnpov_b)
}

* --------------------------------------------------------------------------------------
* 7) PCA (1 component each) + z-score
* --------------------------------------------------------------------------------------
cap noisily pca `Wbasic_in', components(1) correlation
if !_rc {
    cap drop Wbasic_pca1 Wbasic_z
    predict double Wbasic_pca1 if e(sample), score
    egen double Wbasic_z = std(Wbasic_pca1)
}

cap noisily pca `Wutil_in', components(1) correlation
if !_rc {
    cap drop Util_pca1 Util_z
    predict double Util_pca1 if e(sample), score
    egen double Util_z = std(Util_pca1)
}

cap noisily pca `Edu_in', components(1) correlation
if !_rc {
    cap drop Edu_pca1 Edu_z
    predict double Edu_pca1 if e(sample), score
    egen double Edu_z = std(Edu_pca1)
}

cap noisily pca `Hlth_in', components(1) correlation
if !_rc {
    cap drop Hlth_pca1 Hlth_z
    predict double Hlth_pca1 if e(sample), score
    egen double Hlth_z = std(Hlth_pca1)
}
