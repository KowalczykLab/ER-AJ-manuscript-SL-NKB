/*
 * Macro to count foci within an ROI for two channels
 * 
 * Assumes objects of interest in ilastik segmentation file have values of 1 and 2
 * 
 * Output: CSVs for each ROI
 * William Giang
 * 
 */

#@ File (label = "Directory of original tifs", style = "directory") input
#@ File (label = "Directory of ilastik Object Classification results", style = "directory") dir_obj_class
#@ File (label = "Directory of ROIs", style = "directory") dir_ROI
#@ File (label = "Output directory", style = "directory") output
#@ Integer (label = "Minimum size threshold for puncta (in pixels)", value = 3) min_size
#@ String (label = "File suffix", value = ".tif") suffix

setBatchMode(true);

processFolder(input);

close("Log");
close("Summary");
close("Debug");
close("*");
print("Done");

setBatchMode(false);

// function to scan folders/subfolders/files to find files with correct suffix
function processFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	dir_ROI_list = getFileList(dir_ROI);
	dir_ROI_list = Array.sort(dir_ROI_list);
	dir_obj_class_list = getFileList(dir_obj_class);
	dir_obj_class_list = Array.sort(dir_obj_class_list);
	
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(input + File.separator + list[i]))
			processFolder(input + File.separator + list[i]);
		if(endsWith(list[i], suffix))
			processFile(input, output, list[i], dir_ROI_list[i], dir_obj_class_list[i]);
	}
}

function measure_ROI_in_channel(img_name, obj_class_value, iter, min_size){
	selectWindow(img_name);
	roiManager("Select", iter);
	
	// following ilastik's object classification,
	// puncta: 1, linear objects: 2
	
	// for-loop over the classes (starting at 1)
	// assign class variable to be "puncta" (1) or "linear" (2)
	// set the threshold to be 1,1 for puncta and 2,2 for linear objects
	setThreshold(obj_class_value, obj_class_value, "raw");
	
	run("Analyze Particles...", "size="+min_size+"-Infinity display clear overlay composite");
	
	// Measure information about the ROI (Area and Feret) 
	run("Measure");
	ROI_Feret = getResult("Feret");
	ROI_Area = getResult("Area");
	
	IJ.deleteRows( nResults-1, nResults-1 );
	
	// Add info regarding which ilastik object class is chosen {1,2}
	// and particle ID
	
	selectWindow("Results");
	nResultsTable = nResults;
	for (row=0; row < nResultsTable; row++){
		setResult("ObjectClass",row,obj_class_value);
		setResult("ParticleID",row,row);
		setResult("Image", row, img_name);
		setResult("ROI", row, iter);
		setResult("ROI_Area", row, ROI_Area);
		setResult("ROI_Feret", row, ROI_Feret);
	}
	
	saveAs("Results", output + File.separator + img_name+"_ROI-"+iter+"_Class-"+obj_class_value+"_Results.csv");
	close("Results");
}

function processFile(input, output, file, ROI, obj_class_name) {
	// Make sure the ROI Manager has no ROIs at the start
	roiManager("reset");
	close("ROI Manager");
	
	// Open the tif file first
	print(input + File.separator + file);
	open(input + File.separator + file);

	title_orig = getTitle();
	title_no_ext = File.nameWithoutExtension;
	
	// Open the ROIs
	roiManager("Open", dir_ROI + File.separator + ROI);

	// `roiManager("count")` could be used in the for-loop definition,
	// but better practice to initialize before the loop in case
	// ROIs are ever added
	total_ROIs = roiManager("count");

	// Remove Channel Info from all ROIs 
	for (j=0; j < total_ROIs; j++){
		roiManager("Select", j);
		roiManager("Remove Channel Info");
	}
	
	// Open the ilastik Object Classification result file
	open(dir_obj_class + File.separator + obj_class_name);
	title_obj_class = getTitle();
	
	// Use original image for intensity measurements
	run("Set Measurements...", "area mean standard feret's integrated limit display nan redirect="+title_orig+" decimal=3");
	
	// Loop over ROIs
	for (k = 0; k < total_ROIs; k++){
		measure_ROI_in_channel(title_obj_class, 1, k, min_size);
		//measure_ROI_in_channel(title_obj_class, 2, k, min_size);
	}
	
	run("Close All");
}