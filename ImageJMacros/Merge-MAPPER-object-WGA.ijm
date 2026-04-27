/*
 * Objective: Merge WGA channel and object classification result 
 * for Sonam to draw ROIs using the WGA channel
 * 
 * WGA image is 16-bit and calibrated. 
 * The objct classification result is an uncalibrated 8-bit image.
 *  
 * 
 * Assumes nothing else is in the folders but the images
 */


#@ File (label = "Input WGA directory", style = "directory") input_CH1
#@ File (label = "Input object classifiation directory", style = "directory") input_CH2
#@ File (label = "Output directory", style = "directory") output
#@ String (label = "File suffix", value = ".tif") suffix

setBatchMode(true);
list_CH1 = getFileList(input_CH1);
list_CH1 = Array.sort(list_CH1);

list_CH2 = getFileList(input_CH2);
list_CH2 = Array.sort(list_CH2);

for (i = 0; i < list_CH1.length; i++) {
	CH1_file = list_CH1[i];
	CH2_file = list_CH2[i];
	
	
	open(input_CH1 + File.separator + CH1_file );
	run("Enhance Contrast", "saturated=0.35");
	setOption("ScaleConversions", true);
	run("8-bit");
	getVoxelSize(pw, ph, pd, unit);
	
	
	open( input_CH2 + File.separator + CH2_file);
	run("glasbey on dark ");
	
	run("Merge Channels...", "c1=[" + CH2_file + "] c2=[" + CH1_file + "] create");
	setVoxelSize(pw, ph, pd, unit);
	merged_name = substring(CH1_file,0, lengthOf(CH1_file) - 4) + "_WGA_objects-overlay";
	saveAs("tiff", output + File.separator + merged_name);
	run("Close All");
}

setBatchMode(false);