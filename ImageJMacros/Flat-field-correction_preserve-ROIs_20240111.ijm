/*
 * Macro to apply BioVoxxel's flat field correction 
 * for single or multi-channel datasets
 * with/without dark frame calibration
 * for up to two detectors/cameras
 * 
 * 
 * William Giang
 * 
 * Last updated 2024-01-11
 * 
 * 2024-01-11
 *  - unexpectedly, result of the flat field correction does not appear to be active
 *    	so explicitly select the result window
 * 
 * 2023-12-21
 * 	- add script parameter asking about desire for dark frame correction
 * 	- add functionality for including/excluding dark frame correction
 * 		for up to two cameras/detectors
 * 	- add green-magenta LUTs
 * 	- add ability to retain ROIs 
 * 
 * Original 2023-11-21
 */

#@ File (label = "Directory of biological datasets", style = "directory") input
#@ Integer (label = "Number of channels in biological dataset", min=1, max=4, value=3) N_ch
#@ File (label = "Image for flat-field correction of channel 1", style = "file") ch1_ff_calibration
#@ File (label = "Image for flat-field correction of channel 2", style = "file", value="ignore if not used") ch2_ff_calibration
#@ File (label = "Image for flat-field correction of channel 3", style = "file", value="ignore if not used") ch3_ff_calibration
#@ File (label = "Image for flat-field correction of channel 4", style = "file", value="ignore if not used") ch4_ff_calibration
#@ File (label = "Output directory", style = "directory") output
#@ String (label = "File suffix", value = ".tif") suffix
#@ Boolean (label = "Convert to original bit-depth?", value = true) want_original_bitdepth
#@ Boolean (label = "Merge multi-channel datasets?", value = true) want_merged_dataset
#@ Boolean (label = "Want dark frame correction?", value = true) want_dark_frame_correction
#@ File (label = "Image for dark frame correction of first/only detector", style = "file") dark_frame_calibration1
#@ File (label = "Image for dark frame correction of second detector", style = "file") dark_frame_calibration2
#@ String (choices={"Detector 1", "Detector 2"}, style = "radioButtonHorizontal", label="Select channel 1's detector for dark frame correction") detector_ch1
#@ String (choices={"Detector 1", "Detector 2"}, style = "radioButtonHorizontal", label="Select channel 2's detector for dark frame correction") detector_ch2
#@ String (choices={"Detector 1", "Detector 2"}, style = "radioButtonHorizontal", label="Select channel 3's detector for dark frame correction") detector_ch3
#@ String (choices={"Detector 1", "Detector 2"}, style = "radioButtonHorizontal", label="Select channel 4's detector for dark frame correction") detector_ch4
#@ Boolean (label = "Preserve ROIs?", value = false) want_to_save_ROIs

setBatchMode(true);

/*
Check Scale When Converting to have ImageJ scale from min-max to 0-255
when converting from 16-bits or 32-bits to 8-bits 
or to scale from min-max to 0-65535 when converting from 32-bits to 16-bits. 
Note that Scale When Converting is always checked after ImageJ is restarted.
*/
setOption("ScaleConversions", false); 

// Load the flat-field (and possibly dark frame) correction files
ff_array = newArray(ch1_ff_calibration, ch2_ff_calibration, ch3_ff_calibration, ch4_ff_calibration);
ff_names = newArray;
detector_array = newArray(detector_ch1, detector_ch2, detector_ch3, detector_ch4);
dark_names = newArray;

for (i = 0; i < N_ch; i++) {
    run("Bio-Formats Windowless Importer", "open=" + ff_array[i]);
    ff_names[i] = getTitle();

	if (want_dark_frame_correction == true) {
    	if (detector_array[i] == "Detector 2") dark_calibration = dark_frame_calibration2;
    	else dark_calibration = dark_frame_calibration1;
    	
    	run("Bio-Formats Windowless Importer", "open=" + dark_calibration);
    	dark_names[i] = getTitle();
    }   
}
print("Dark names:");
Array.print(dark_names);

// Basic template function
processFolder(input);

// Clean up
run("Close All");
setBatchMode(false);
print("Done");

// function to scan folders/subfolders/files to find files with correct suffix
function processFolder(input) {
	list = getFileList(input);
	list = Array.sort(list);
	for (i = 0; i < list.length; i++) {
		if(File.isDirectory(input + File.separator + list[i]))
			processFolder(input + File.separator + list[i]);
		if(endsWith(list[i], suffix))
			processFile(input, output, list[i]);
	}
}

function processFile(input, output, file) {
	
	print("Processing: " + input + File.separator + file);

	// switching from Bio-Formats Windowless Importer to the ImageJ open because this plays nicer with ROIs/overlays
	open(input + File.separator + file);
	//run("Bio-Formats Windowless Importer", "open=" + input + File.separator + file);

	// Store info
	title_orig = getTitle();
	title_no_ext = File.nameWithoutExtension;
	
	getDimensions(width, height, channels, slices, frames);
	bitdepth = bitDepth();
	selectWindow(title_orig);
	if (want_to_save_ROIs) run("To ROI Manager");

	// assert with (maybe) a better error message than with Fiji would give
	if (channels != N_ch) exit("Number of channels in dataset does not match `Number of channels in biological dataset`");
	
	// BioVoxxel's function only works on single-channel datasets
	if (channels > 1) {run("Split Channels");}
	
	corrected_channel_names = newArray(channels);
	
	for (ch = 1; ch <= channels; ch++) {
		if (channels > 1 ){
			ch_title = "C" + ch + "-" + title_orig;
			ch_title_no_ext = "C" + ch + "-" + title_no_ext;
		}
		else {
			ch_title = title_orig;
			ch_title_no_ext = title_no_ext;
		}
		selectWindow(ch_title);
		
		flat_field_correction_str = "originalimageplus=" + ch_title + " flatfieldimageplus=" + ff_names[ch-1];
		if (want_dark_frame_correction == false) dark_name = "None";
		else dark_name = dark_names[ch-1];
		
		flat_field_correction_str = flat_field_correction_str + " darkfieldimagename=" + dark_name;
		run("Flat Field Correction (2D/3D)", flat_field_correction_str);
		// unexpectedly, result of the flat field correction does not appear to be active
		// so explicitly select the result window
		selectWindow("FFCorr_" + ch_title_no_ext + "-1" + suffix);
		
		if (want_original_bitdepth) {run(bitdepth + "-bit");}
		
		corrected_channel_names[ch-1] = getTitle();
	}
	
	// Save results
	
	// 		Save merged multi-channel
	if (channels > 1 && want_merged_dataset){
		
		merge_channels_str = buildMergeChannelsString(channels, corrected_channel_names);
		print(merge_channels_str);
		run("Merge Channels...", merge_channels_str);
		
		// Steph wants YMC LUTs for her 3-channel datasets
		// comment out or adapt for future use--don't have time to generalize now
		//assignYMC();
		
		// Sonam wants green-magenta LUTs 
		// comment out or adapt for future use--don't have time to generalize now
		assignGM();
		
		if (want_to_save_ROIs) {
			run("From ROI Manager");
			roiManager("Delete");
		}
		
		//saveAs("Tiff", output + File.separator + "FFCorr_" + title_no_ext);
		saveAs("Tiff", output + File.separator + title_no_ext);
	}
	
	//		Save individual channels
	else{
		for (ch = 1; ch <= channels; ch++) {
			selectWindow(corrected_channel_names[ch-1]);
			saveAs("Tiff", output + File.separator + corrected_channel_names[ch-1]);
		}
	}

	closeWindowsExceptForSelected(ff_names, dark_names);
}

function buildMergeChannelsString(N_channels, corrected_channel_names) {
	// Create the command string for Merge Channels
	cmd_concat = "";
	for (i = 1; i <= N_channels; i++) {
		str_concat = "c" + i + "=" + corrected_channel_names[i-1];
		cmd_concat = cmd_concat + " " + str_concat;
		}
	
	cmd_concat = cmd_concat + " create";
	
	return cmd_concat;
}

function arrayContains(array, element) {
	for (i = 0; i < array.length; i++) {
		if (array[i] == element) 
			return true;
	}
	return false;
}

function closeWindowsExceptForSelected(calibration_image_array, dark_image_array) {
	selected_image_array = Array.concat(calibration_image_array, dark_image_array);
	
	all_images = getList("image.titles");

	// Loop over all open image windows
	for (i = 0; i < lengthOf(all_images); i++) {
		selectWindow(all_images[i]);
		title = getTitle();
		// Check to see if the image is needed
		if (!arrayContains(selected_image_array, title)){
			close(title);
		}
	}
}

function assignYMC() {
	setSlice(1);
	run("Yellow");
	setSlice(2);
	run("Magenta");
	setSlice(3);
	run("Cyan");
}

function assignGM() {
	setSlice(1);
	run("Green");
	setSlice(2);
	run("Magenta");
}
