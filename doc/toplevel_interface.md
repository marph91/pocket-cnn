# Toplevel interface

| <center>Generic/Signal</center> | <center>Datatype</center> | <center>Meaning</center> |
| :--- | :--- | :--- |
| C_PE | Integer | Number of processing elements (PE). A PE consists of one convolution layer and some optional layers. See the documentation folder for more details. |
| C_DATA_TOTAL_BITS | Integer | Bitwidth of the whole design. Currently limited to 8 bit. |
| C_BITWIDTH | Array of integer, C_PE elements | Specific bitwidths for data and weights of each layer. |
| C_IMG_WIDTH_IN | Integer | Width of the input image. |
| C_IMG_HEIGHT_IN | Integer | Height of the input image. |
| C_CH | Array of integer, C_PE+1 elements | Channel of each layer. The first element corresponds to the depth of the input image, i. e. 1 for grayscale and 3 for colored. |
| C_PARALLEL_CH | Array of integer, C_PE elements | Intra kernel parallelization for each PE. |
| isl_clk | std_logic | Clock signal. |
| isl_get | std_logic | Signals that the next module is ready to process new data. |
| isl_start | std_logic | Start receiving the image data and process it afterwards. |
| isl_valid | std_logic | Signals valid input data. |
| islv_data | std_logic_vector, C_DATA_TOTAL_BITS bits | Input data. |
| oslv_data | std_logic_vector, C_DATA_TOTAL_BITS bits | Output data. |
| osl_valid | std_logic | Signals valid output data. |
| osl_rdy | std_logic | Signals that the module is ready to process new data. |
| osl_finish | std_logic | Impulse for signalling that the processing of the current image is finshed. Can be used for an interrupt. |
