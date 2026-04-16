# ==============================================================================
# HOCS (Hybrid Optical Computing System) - Vivado Project Build Script
# Target: Xilinx Kria K26 SOM (xck26-sfvc784-2LV-c)
# ==============================================================================

# 1. Proje Ayarları
set project_name "HOCS_Kria_Core"
set project_dir "./vivado_project"
set target_part "xck26-sfvc784-2LV-c" 
set board_part "xilinx.com:kv260_som:part0:1.3" ;# Kria KV260/K26 base

puts "\[HOCS-BUILD\] Bismillah. Xilinx Kria K26 icin $project_name projesi olusturuluyor..."

# Eski proje varsa temizle (Acımasız mod)
if {[file exists $project_dir]} {
    file delete -force $project_dir
    puts "\[HOCS-BUILD\] Eski proje kalintilari temizlendi."
}

# 2. Projeyi Yarat
create_project $project_name $project_dir -part $target_part
set_property board_part $board_part [current_project]
set_property target_language SystemVerilog [current_project]
set_property simulator_language Mixed [current_project]

# 3. Kaynak Kodlari (HDL) Ekle
puts "\[HOCS-BUILD\] Donanim mimarisi (HDL) kaynaklari projeye enjekte ediliyor..."
add_files -fileset sources_1 [glob -nocomplain ../src/hdl/*.v]
add_files -fileset sources_1 [glob -nocomplain ../src/hdl/*.sv]

# 4. Simülasyon (Testbench) Kodlarini Ekle
puts "\[HOCS-BUILD\] Testbench dosyalari simülasyon setine ekleniyor..."
add_files -fileset sim_1 [glob -nocomplain ../src/tb/*.v]
add_files -fileset sim_1 [glob -nocomplain ../src/tb/*.sv]
set_property top tb_hocs_kria_k26_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# 5. Top Module Belirleme
set_property top hocs_kria_k26_top [current_fileset]

# 6. Zynq UltraScale+ PS (Islemci) Blogunun Olusturulmasi
puts "\[HOCS-BUILD\] ARM Cortex-A53 (PS) blogu olusturuluyor..."
create_bd_design "hocs_ps_block"
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.3 zynq_ultra_ps_e_0
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1" }  [get_bd_cells zynq_ultra_ps_e_0]
save_bd_design
close_bd_design [get_bd_designs hocs_ps_block]

# 7. Sentez (Synthesis) Ayarlari - Maksimum Performans ve DSP Kullanimi Icin
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AlternateRoutability [get_runs synth_1]

puts "\[HOCS-BUILD\] Proje basariyla insa edildi. Vivado GUI uzerinden calismaya hazir."
puts "\[HOCS-BUILD\] ==================================================================="
puts "\[HOCS-BUILD\] Adim 1: 'Run Simulation' ile optik kilitlenmeyi (Lane Lock) test et."
puts "\[HOCS-BUILD\] Adim 2: 'Run Synthesis' ile Kria K26 kaynak kullanimini (DSP/BRAM) gor."
