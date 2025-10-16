// Get the file that you want to process (must be a single slice, single frame, multi-channel image).
#@ File (label="Choose directory with images to process (multi-channel is ok, but must be 1z and 1t)", style = "directory") dir_input
#@ File (label="Choose directory for creating result folders (one level above input data dir?)", style = "directory") dir_main
#@ File (label="Choose directory with ROIs (assumed to be named identically to the images", style = "directory") dir_rois
#@ Integer (label="Number of concentric rings", value = 256) N_rings
#@ Boolean (label="Check box if you want radial color coding", value=true) want_color_coding
#@ String (label="LUT for color coding", choices={"Fire", "Spectrum", "Ice"}, style="listBox") lut_for_color_coding
#@ Boolean(label="Check if you want your ROIs to be smoothed by a spline", value=true) want_fit_spline

//setBatchMode(true);

// Fiji settings
setOption("BlackBackground", true);
run("Set Measurements...", "area mean standard min integrated area_fraction stack display nan redirect=None decimal=3");

n_slices = N_rings - 1;


// Create directories to save: 
// - ROIs
// - colorcoded images to show ROIs
// - intensity meaasurements in CSV files
// - cropped images to show spacing of circles

//dir_rois         = dir_main + File.separator + "ROIs"                  + File.separator;
dir_color_coded  = dir_main + File.separator + "ColorCoded"            + File.separator;
dir_measurements = dir_main + File.separator + "IntensityMeasurements" + File.separator;
dir_cropped      = dir_main + File.separator + "Cropped"               + File.separator;


//File.makeDirectory(dir_rois);
File.makeDirectory(dir_color_coded);
File.makeDirectory(dir_measurements);
File.makeDirectory(dir_cropped);

list = getFileList(dir_input);

for (i = 0; i< list.length; i++) {
	filename = list[i];
	
	if (endsWith(filename, ".tif")) {
		
		// Load image and store info
		open(dir_input + File.separator + filename);

		filebase = File.nameWithoutExtension;
		image_orig_name = getTitle();
		getDimensions(_, _, N_channels, _, _);
		
		// Get number of cells to analyze 
		// Get ROIs
		roiManager("reset");
		roiManager("Open", dir_rois + File.separator + filebase + ".zip");
		N_ROI = roiManager("count");
		// two ROIs per cell: 1) nucleus 2) cell boundary
		N_cells = N_ROI / 2;
		
		for (cell = 1; cell <= N_cells; cell++){
			NucToPM(dir_input, dir_rois, filebase, image_orig_name, cell);
		}
		close("*");
	}
}


function buildConcatenateStringFromC(N_channels, prefix) {
	// Create the command string for Concatenate for multiple channels
	cmd_concat = "open";
	for (i = 1; i <= N_channels; i++) {
		str_concat = "image" + i + "=" + prefix + i;
		cmd_concat = cmd_concat + " " + str_concat;
		}
	
	return cmd_concat;
}

function keepCertainROIs(cell_number){
	N_ROIs = roiManager("count");
	
	first_ROI_index_to_keep = (cell_number - 1) * 2;
	ROIs_to_keep = newArray(first_ROI_index_to_keep, first_ROI_index_to_keep + 1);
		
	// Build array of ROIs to delete
	ROIS_to_delete = newArray;
	index = 0;
	
	for (i=0; i < N_ROIs; i++){
		if ( (i != ROIs_to_keep[0]) && (i != ROIs_to_keep[1])){
			ROIS_to_delete[index] = i;
			index++;
			}
		}
	// If the number of ROIs is 2, then ROIS_to_delete is empty
	// but without this if-statement, the desired ROIs are deleted
	if (ROIS_to_delete.length > 0){
		roiManager("Select", ROIS_to_delete);
		roiManager("Delete");
	}
	
}

function NucToPM(dir_input, dir_rois, filebase, image_orig_name, cell){

	// One image per "cell"
	// Do this because overlay/ROI positions are not preserved after cropping/duplicating
	selectWindow(image_orig_name);
	run("Duplicate...", "title=" + filebase + "_cell-" + String.pad(cell, 3) + ".tif duplicate");
	img_cell = getTitle();
	print("img_cell:" + img_cell);
	
	// Get ROIs
	roiManager("reset");
	roiManager("Open", dir_rois + File.separator + filebase + ".zip");
	
	keepCertainROIs(cell);
		
	// TODO: Make the macro work on single channel images?
	run("Split Channels");
	
	// --------------------------------------------------------------------------------------------------------------------

	setBatchMode("hide");
	for(channel = 1; channel <= N_channels; channel++){
		C_str = "C" + channel;
		selectWindow(C_str + "-" + img_cell);
		
		for (i=0; i < n_slices; i++){
			run("Duplicate...", "title=&C_str");
			rename(C_str);
		}
		run("Images to Stack", "name="+C_str+" title=" + C_str+"  use");
		rename(C_str);
	}
	
	setBatchMode("exit and display");
// -----------------------------------------------------------------------------------------



	// ROI of the nucleus on slice 1 and an ROI of the plasma membrane on slice N_Rings then interpolate between them	
	// https://forum.image.sc/t/macro-how-to-add-slice-information-to-a-selection/3259/6
	// learned about ROI naming convention today!
	
	selectWindow("C1");
	roiManager("Select", 0);
	if (want_fit_spline) run("Fit Spline");
	Stack.setSlice(1);
	roiManager("update");
	roiManager("Rename", "0001-0000-0000");

	//roiManager("Add");
	//run("Select None");	
	//Stack.setSlice(N_rings);
	roiManager("Select", 1);
	if (want_fit_spline) run("Fit Spline");
	Stack.setSlice(N_rings);
	roiManager("update");
	roiManager("Rename", String.pad(N_rings, 4) + "-0000-0000" + "_" + img_cell);
	
	
	roiManager("Interpolate ROIs");	
	//Stack.setSlice(1);
	//run("Select None");	//WG: why delete??


	//-----------------------------------------------------------------------------------------------------------------
	// In order to calculate the area and intensity of each ring, slice the image into concentric polygons of increasing size. 
	// As a somewhat hacky solution, clear outside of the selected slice, jump to the next slice (j+1), and clear a portion of the image the size of j.
	// so for j = 0 (ROI 0), we clear everything outside the nucleus (which stays). I don't know if it's necessary or not--but better to keep it.
	// Ignore the values later in the analysis if unwanted.
	// When we then iterate to the next value of j, we clear inside and now that gives a ring of intensity values surrounded by 0 value background
	// If N_rings = 255, then Roi #254 corresponds to the second to last slice 
	// The images are 1-indexed but the ROIs are 0-indexed.
	// This will give a stack with a nucleus in the first slice, 254 ring slices, and 1 final slice that has not been cropped..we'll handle that below.
	
	for(channel = 1; channel <= N_channels; channel++){
		C_str = "C" + channel;
		selectWindow(C_str);
		resetMinAndMax();
		
		run("Add...", "value=1 stack"); // This will be important later to ensure that there are no 0 value pixels in the signal. 0 value will thus just be cropped background.  
		
		for (j=0; j < n_slices; j++) {
			roiManager("Select", j);
			run("Clear Outside", "slice");
			run("Next Slice [>]");
			run("Clear", "slice");
			}
		
		// This will clear the final area outside of the final slice to complete the picture
		roiManager("Select", n_slices);
		run("Clear Outside", "slice");
	
		run("32-bit"); // making it 32 bit so we can convert the 0 to nan background
		setThreshold(1, 4294967295, "raw"); // Your background is always 0 and foreground is > 0.
		run("NaN Background", "stack"); // Make the background not a number
		run("Subtract...", "value=1 stack"); // Correct for the +1 earlier
		im_for_stats = getTitle();
		run("Statistics"); // Get stats (ignores NaNs) to get min and max values for the whole stack to set the display for the eventual 8 bit conversion
		MaxValue = getResult("Max", 0);
		//print(MaxValue);
		MinValue = getResult("Min",0);
		//print(MinValue);
		setMinAndMax(MinValue, MaxValue);
		table_name_ThresholdedStackRawIntDen = C_str + "ThresholdedStackRawIntDen";
		Table.rename("Results", table_name_ThresholdedStackRawIntDen); // This has the max and min info...we don't really need it but I wanted to rename the table
		
		//-----------
		selectWindow(im_for_stats);
		run("Measure Stack...");
		table_name_int = C_str + "_IntensityInformation";
		Table.rename("Results", table_name_int);
		saveAs("results", dir_measurements + img_cell + "_"+ C_str + "_Intensity.csv"); // This is the good stuff with intensity values.  You really only need to set area and integrated.
		
		// Clean up
		close(table_name_ThresholdedStackRawIntDen);
		close(table_name_int);
		
		if (want_color_coding) {
			selectWindow(C_str);
			
			run("8-bit"); // Sets the display range of the active image to min and max
			
			run("Temporal-Color Code", "lut=" + lut_for_color_coding + " start=1 end=" + N_rings);
			rename("Colored_" + C_str); // useful for later concatenation
			
			if (N_channels == 1){ // not possible in the current iteration of this code since it needs multi-channel data
				saveAs("Tiff", dir_color_coded + File.separator + img_cell + "_ColorCoded");
			}
		}
	}
	
	if (want_color_coding){
		cmd_concat = buildConcatenateStringFromC(N_channels, "Colored_C");
		run("Concatenate...", cmd_concat);
		saveAs("Tiff", dir_color_coded + File.separator + img_cell + "_ColorCoded");
	}
	

	cmd_concat = buildConcatenateStringFromC(N_channels, "C");
	run("Concatenate...", cmd_concat);
	run("Stack to Hyperstack...", "order=xyctz channels=" + N_channels + " slices=" + N_rings + " frames=1 display=Composite");
	saveAs("Tiff", dir_cropped + File.separator + img_cell + "_Cropped");
	
	// clean up
	//close("*");
}

setBatchMode(false);