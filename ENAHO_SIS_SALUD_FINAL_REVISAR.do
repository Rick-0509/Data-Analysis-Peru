
clear all
set more off
capture log close

* --- 0. CONFIGURACION: AJUSTA ESTAS RUTAS -----------------------------------

global carpeta "C:\Users\Comercial-LT03\OneDrive\Escritorio\LTB"   // <-- ajusta si aplica
capture cd "$carpeta"
if _rc {
    di as error "No se pudo entrar a la carpeta: $carpeta"
    di as error "Verifica que la ruta sea exactamente esa (mayusculas, Ñ, tildes, OneDrive)."
}
di as text "Directorio actual:"
pwd
capture log close
capture log using "$carpeta\log_enaho_2024_2025.log", replace text
if _rc {
    di as text "(Aviso: no se pudo crear el log en esa carpeta -- probablemente OneDrive. Se continua sin log.)"
}

* Modulo 400 = Salud (afiliacion SIS / EsSalud) -- YA CONFIRMADO
local mod400_2024  "$carpeta\AÑO 2024\4-SALUD\enaho01a-2024-400.dta"
local mod400_2025  "$carpeta\AÑO 2025\1031-Modulo04\enaho01a-2025-400.dta"

* Modulo 500 = Empleo e Ingresos -- CONFIRMADO
local mod500_2024  "$carpeta\AÑO 2024\966-EMPLEO Y SEGURO\enaho01a-2024-500.dta"
local mod500_2025  "$carpeta\AÑO 2025\1031-Modulo05\enaho01a-2025-500.dta"

* Modulo 34 = Sumaria (factor07, mes, dominio) -- CONFIRMADO
* Usamos la version estandar (no la "-12g", que es la version con 12 dominios
* geograficos; cambia la ruta si tu practica pide esa desagregacion).
local sumaria_2024 "$carpeta\AÑO 2024\34-SUMARIA VARIABLES CALCULADAS\sumaria-2024.dta"
local sumaria_2025 "$carpeta\AÑO 2025\1031-Modulo34\sumaria-2025.dta"

* Diagnostico: verifica cada archivo y muestra la ruta exacta que se probo
di as text "--- Verificando archivos de 2024 ---"
foreach ruta in `"`mod400_2024'"' `"`mod500_2024'"' `"`sumaria_2024'"' {
    capture confirm file `"`ruta'"'
    if _rc di as error "NO ENCONTRADO: `ruta'"
    else   di as result "OK: `ruta'"
}

* --- 1. Columnas de SIS y EsSalud -- CONFIRMADO con "describe p419*" en 2024:
*    p4191 = ESSALUD
*    p4195 = SIS  (confirmado por el label de p419a5: "seguro integral de
*                  salud (sis)")
*    p4192=seguro privado, p4193=EPS, p4194=FFAA/policial,
*    p4196=universitario, p4197=escolar privado, p4198=otro
*    Estas columnas vienen en 1 si la persona marco esa opcion, y en blanco
*    (missing) si no la marco.
capture program drop detecta_seguros
program define detecta_seguros
    capture confirm variable p4191
    if _rc {
        di as error "No se encontro p4191 en este archivo. Revisa el diccionario de este anio."
        exit 111
    }
    capture confirm variable p4195
    if _rc {
        di as error "No se encontro p4195 en este archivo. Revisa el diccionario de este anio."
        exit 111
    }
    rename p4191 afil_essalud
    rename p4195 afil_sis
end

* --- 2. PROGRAMA: procesa un anio completo ----------------------------------
capture program drop procesa_anio
program define procesa_anio
    args anio mod400 mod500 sumaria

    *--- 2.1 Modulo 400: aseguramiento de salud ---
    use conglome vivienda hogar codperso p419* using "`mod400'", clear
    detecta_seguros

    * Codificacion confirmada (Diccionario 2025, y consistente en 2024):
    * 1 = Si esta afiliado a ese seguro, 2 = No, "." = no aplica/missing.
    * Se trata TODO lo que no sea exactamente 1 como "no afiliado" (0),
    * incluyendo el codigo 2 y los missing.
    gen byte sis     = (afil_sis==1)
    gen byte essalud = (afil_essalud==1)

    gen solo_sis     = (sis==1     & essalud==0)
    gen solo_essalud = (essalud==1 & sis==0)

    tempfile base200
    save `base200'

    *--- 2.2 Modulo 500: ingreso de la ocupacion principal ---
   
    use conglome vivienda hogar codperso i524a1 i530a ocu500 using "`mod500'", clear
    capture confirm variable i524a1
    if _rc {
        di as error "No se encontro i524a1 en el modulo 500 de este anio."
        di as error "Corre 'describe I5*' y 'describe I52*' sobre ese archivo y ajusta el nombre."
        exit 111
    }
    capture confirm variable i530a
    if _rc {
        di as error "No se encontro i530a en el modulo 500 de este anio."
        di as error "Corre 'describe I5*' y 'describe I53*' sobre ese archivo y ajusta el nombre."
        exit 111
    }
    egen ingreso_principal = rowtotal(i524a1 i530a), missing
    keep conglome vivienda hogar codperso ingreso_principal ocu500
    tempfile base500
    save `base500'

    *--- 2.3 Sumaria: factor de expansion (para ponderar poblacion) ---
    use conglome vivienda hogar factor07 using "`sumaria'", clear
    tempfile basesum
    save `basesum'

    *--- 2.4 Unir las tres bases ---
    use `base200', clear
    merge 1:1 conglome vivienda hogar codperso using `base500', keep(match) nogenerate
    merge m:1 conglome vivienda hogar using `basesum', keep(match) nogenerate

    *--- 2.5 Ingreso ya viene imputado/deflactado/anualizado desde INEI ---
    * No se requiere ningun ajuste adicional: i524a1/i530a ya cumplen los
    * tres requisitos del enunciado (imputado, deflactado, anualizado).
    gen ingreso_anual = ingreso_principal

    gen anio = `anio'
    save "`c(tmpdir)'procesado_`anio'.dta", replace
end

* --- 3. EJECUTAR PARA 2024 Y 2025 -------------------------------------------
* Verifica que los archivos existan antes de procesar cada anio, para poder
* correr ya con 2024 aunque 2025 todavia no este descargado.
local anios_ok ""

capture confirm file "`mod400_2024'"
local ok400_24 = (_rc==0)
capture confirm file "`mod500_2024'"
local ok500_24 = (_rc==0)
capture confirm file "`sumaria_2024'"
local oksum_24 = (_rc==0)

if `ok400_24' & `ok500_24' & `oksum_24' {
    procesa_anio 2024 "`mod400_2024'" "`mod500_2024'" "`sumaria_2024'"
    local anios_ok "`anios_ok' 2024"
}
else {
    di as error "2024: falta al menos un archivo (revisa mod400_2024/mod500_2024/sumaria_2024). Se omite 2024."
}

capture confirm file "`mod400_2025'"
local ok400_25 = (_rc==0)
capture confirm file "`mod500_2025'"
local ok500_25 = (_rc==0)
capture confirm file "`sumaria_2025'"
local oksum_25 = (_rc==0)

if `ok400_25' & `ok500_25' & `oksum_25' {
    procesa_anio 2025 "`mod400_2025'" "`mod500_2025'" "`sumaria_2025'"
    local anios_ok "`anios_ok' 2025"
}
else {
    di as text "2025: archivos aun no disponibles. Se omite 2025 por ahora (normal si todavia no los descargas)."
}

if "`anios_ok'" == "" {
    di as error "No se encontro ningun anio con los 3 archivos completos. Revisa las rutas de la seccion 0."
    exit 601
}

* Cargar los anios que si se procesaron (2024, y 2025 si ya esta disponible)
local primero = 1
foreach a in `anios_ok' {
    if `primero' == 1 {
        use "`c(tmpdir)'procesado_`a'.dta", clear
        local primero = 0
    }
    else {
        append using "`c(tmpdir)'procesado_`a'.dta"
    }
}

label define lgrupo 1 "Solo SIS" 2 "Solo EsSalud"
gen grupo = .
replace grupo = 1 if solo_sis==1
replace grupo = 2 if solo_essalud==1
label values grupo lgrupo

* --- 4. CUADRO 1: Poblacion afiliada (Solo SIS / Solo EsSalud) 2024-2025 ---
preserve
    gen pob_exp = factor07 if !missing(grupo)
    keep if !missing(grupo)
    collapse (sum) pob_exp, by(anio grupo)
    reshape wide pob_exp, i(grupo) j(anio)
    * Renombrar solo las columnas de anio que si existen (por si aun no
    * tienes 2025 procesado)
    capture rename pob_exp2024 poblacion2024
    capture rename pob_exp2025 poblacion2025
    export excel using "Cuadro1_Poblacion_SIS_EsSalud.xlsx", firstrow(variables) replace
    list
restore

* --- 5. CUADRO 2: Ingreso promedio ocupacion principal (imp/defl/anual) ----
preserve
    keep if !missing(grupo)
    collapse (mean) ingreso_prom=ingreso_anual [pweight=factor07], by(anio grupo)
    reshape wide ingreso_prom, i(grupo) j(anio)
    capture rename ingreso_prom2024 ingreso2024
    capture rename ingreso_prom2025 ingreso2025
    export excel using "Cuadro2_Ingreso_Promedio_SIS_EsSalud.xlsx", firstrow(variables) replace
    list
restore

capture log close
