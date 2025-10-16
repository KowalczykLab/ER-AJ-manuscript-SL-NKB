/*
 * 2024-11-13
 * William Giang
 * 
 * for Sonam Lhamo
 * 
 * Objectives: 
 * 	
 * 	After connected components labeling, filter by size, relabel, and measure 3D centroid position
 *  
 *  Plan to re-combine the tables using Python (or other language of choice).
 * 
 * Input: 
 * 	- single-channel z-stacks of simple segmentation results from ilastik
 * Output: csv file
 * 
 * Assumes nothing else is in the folders but the images
 */


#@ File    (label = "Input ilastik results directory",  style = "directory") input_dir
#@ String  (label = "CH1 name", value="MAPPER") CH1_name
#@ Integer (label = "Minimum Size for Label Size Filtering of CH1", value=10) min_label_size1
#@ String  (label = "Table name 1", value="z-position")  table1
#@ File    (label = "Output directory", style = "directory") output

function makeLabelImageThenSizeFilterAndRemap(binary_mask_image, min_label_size, label_image_name) {
	selectWindow(binary_mask_image);
	run("Connected Components Labeling", "connectivity=26 type=[16 bits]");
	run("Label Size Filtering", "operation=Greater_Than size="+min_label_size);
	run("Remap Labels");
	remapped_orig_name = getTitle();
	remapped_orig_name_no_ext = removeExtension(remapped_orig_name);
	selectWindow(remapped_orig_name);
	rename(label_image_name);
	
	// clean up intermediate image
	name_without_ext = removeExtension(binary_mask_image);
	close(name_without_ext+"-lbl");
}


function makeBinaryMaskFromSimpleSegmentation(simple_seg_image, desired_value, mask_name) { 
	selectWindow(simple_seg_image);
	setThreshold(desired_value, desired_value, "raw");
	setOption("BlackBackground", true);
	run("Convert to Mask", "background=Dark black create");
	//resulting image has a "MASK_" prefix
	
	tmp = getTitle();
	selectWindow(tmp);
	rename(mask_name);
	
	// reset things just in case
	selectWindow(simple_seg_image);
	resetThreshold;
}

function get3DCentroidInfo(label_img, main_row_to_write, table, suffix_for_column_header, min_label_size) {
	selectWindow(label_img);

	run("Analyze Regions 3D", "centroid surface_area_method=[Crofton (13 dirs.)] euler_connectivity=26");

	input_img_name_without_ext = removeExtension(label_img);
	temp_table_name = input_img_name_without_ext + "-morpho";

	Table.rename(Table.title, temp_table_name);
	
	row_to_write = main_row_to_write;

	for (z = 0; z < Table.size; z++) {
	    label_obj = Table.getString("Label",    z, temp_table_name);
	    CentX     = Table.get("Centroid.X",     z, temp_table_name);
	    CentY     = Table.get("Centroid.Y",     z, temp_table_name);
	    CentZ     = Table.get("Centroid.Z",     z, temp_table_name);
	    
	    //Mean_int  = Table.get("Mean",           z, temp_table_name);
	    //StdDev    = Table.get("StdDev",         z, temp_table_name);
	    //Max       = Table.get("Max",            z, temp_table_name);
	    //NVoxels   = Table.get("NumberOfVoxels", z, temp_table_name);
	    //Volume    = Table.get("Volume",         z, temp_table_name);
	    
	    Table.set("img",        row_to_write, input_img_name_without_ext, table);
	    Table.set("Centroid.X"+suffix_for_column_header, row_to_write, CentX, table);
	    Table.set("Centroid.Y"+suffix_for_column_header, row_to_write, CentY, table);
	    Table.set("Centroid.Z"+suffix_for_column_header, row_to_write, CentZ, table);
	    Table.set("nSlices"                            , row_to_write, nSlices, table);
	    Table.set("Total_Height"                       , row_to_write, nSlices*0.45, table);
	    Table.set("Label",   row_to_write, label_obj, table);

	    row_to_write += 1;
	    Table.update;
	}
	close(temp_table_name);
	
	return row_to_write;
}

setBatchMode(true);

list_input = getFileList(input_dir);
list_input = Array.sort(list_input);

Table.create(table1);
var table1_row_to_write = 0;


for (i = 0; i < list_input.length; i++) {	
	// Load, assign physical dimensions, and split probability images
	hyperstack = list_input[i];
	hyperstack_with_path = input_dir + File.separator + hyperstack;
	
	run("Import HDF5", "select=["+hyperstack_with_path+"] datasetname=/exported_data axisorder=zyxc");
	h5_name = getTitle();
	selectWindow(h5_name);
	rename(hyperstack);
	setVoxelSize(0.065, 0.065, 0.45, "micron"); // 100x objective, no intermediate mag
	print(hyperstack_with_path);
	
	fname_no_ext = File.nameWithoutExtension;
	c1 = hyperstack;
	
	// using probability images, create binary masks and label images 
	c1_mask_name_before_filtering = "c1_mask.tif";
	
	makeBinaryMaskFromSimpleSegmentation(hyperstack, 1, c1_mask_name_before_filtering);
	
	c1_no_ext = removeExtension(c1);
	c1_label_image_name = c1_no_ext + "_lbl-sizeFilt.tif";
	
	makeLabelImageThenSizeFilterAndRemap(c1_mask_name_before_filtering, min_label_size1, c1_label_image_name);

	table1_row_to_write = get3DCentroidInfo(c1_label_image_name, table1_row_to_write, table1, "_"+CH1_name, min_label_size1);
	
	run("Close All");
}


// Save tables and close.
// Looks unnecessary because this macro was modified 
// from a macro with multiple tables to be saved.

tables_arr = newArray(table1);
for (t=0; t < tables_arr.length; t++){
	selectWindow(tables_arr[t]);
	tmp_table_save_name = tables_arr[t] + ".csv";
	saveAs("Results", output + File.separator + tmp_table_save_name);
	close(tmp_table_save_name);
}

setBatchMode(false);