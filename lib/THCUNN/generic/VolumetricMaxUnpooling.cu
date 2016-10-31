#ifndef THC_GENERIC_FILE
#define THC_GENERIC_FILE "generic/VolumetricMaxUnpooling.cu"
#else

void THNN_(VolumetricMaxUnpooling_updateOutput)(
           THCState *state,
           THCTensor *input,
           THCTensor *output,
           THCIndexTensor *indices,
           int outputTime, int outputWidth, int outputHeight,
           int dT, int dW, int dH,
           int padT, int padW, int padH)
{
  int batchSize;
  int inputSlices;
  int inputTime;
  int inputHeight;
  int inputWidth;

  THCUNN_assertSameGPU_generic(state, 3, input, indices, output);

  if (THCTensor_(nDimension)(state, input) == 4)
  {
    /* sizes */
    batchSize   = 1;
    inputSlices = THCTensor_(size)(state, input, 0);
    inputTime   = THCTensor_(size)(state, input, 1);
    inputHeight = THCTensor_(size)(state, input, 2);
    inputWidth  = THCTensor_(size)(state, input, 3);
  }
  else if (THCTensor_(nDimension)(state, input) == 5)
  {
    /* sizes */
    batchSize   = THCTensor_(size)(state, input, 0);
    inputSlices = THCTensor_(size)(state, input, 1);
    inputTime   = THCTensor_(size)(state, input, 2);
    inputHeight = THCTensor_(size)(state, input, 3);
    inputWidth  = THCTensor_(size)(state, input, 4);
  }
  else
  {
    THArgCheck(false, 2, "4D or 5D tensor expected");
  }

  if (input->nDimension == 4) /* 4D */
  {
    /* resize output */
    THCTensor_(resize4d)(state, output, inputSlices,
                          outputTime, outputHeight, outputWidth);
  }
  else
  { /* 5D */
    THCTensor_(resize5d)(state, output, batchSize, inputSlices,
                          outputTime, outputHeight, outputWidth);
  }

  input = THCTensor_(newContiguous)(state, input);
  indices = THCIndexTensor_(newContiguous)(state, indices);
  THCTensor_(zero)(state, output);

  // Collapse batch and feature dimensions
  THCDeviceTensor<real, 4> cudaInput;
  THCDeviceTensor<real, 4> cudaOutput;
  THCDeviceTensor<THCIndex_t, 4> cudaIndices;

  if (THCTensor_(nDimension)(state, input) == 4)
  {
    cudaInput  = toDeviceTensor<real, 4>(state, input);
    cudaOutput = toDeviceTensor<real, 4>(state, output);
    cudaIndices = toDeviceTensor<THCIndex_t, 4>(state, indices);
  }
  else
  {
    cudaInput  = toDeviceTensor<real, 5>(state, input).downcastOuter<4>();
    cudaOutput = toDeviceTensor<real, 5>(state, output).downcastOuter<4>();
    cudaIndices = toDeviceTensor<THCIndex_t, 5>(state, indices).downcastOuter<4>();
  }

  int totalZ = inputTime * inputSlices * batchSize;
  int offsetZ = 0;
  dim3 block(32, 8);

  while (totalZ > 0) {
    dim3 grid(THCCeilDiv(inputWidth, static_cast<int>(block.x)),
              THCCeilDiv(inputHeight, static_cast<int>(block.y)),
              totalZ > 65535 ? 65535 : totalZ);

    cuda_VolumetricMaxUnpooling_updateOutput<<<grid, block,
          0, THCState_getCurrentStream(state)>>>(
                             cudaInput, cudaIndices, cudaOutput,
                             dT, dH, dW,
                             padT, padH, padW, offsetZ);
    THCudaCheck(cudaGetLastError());
    totalZ -= 65535;
    offsetZ += 65535;
  }

  THCTensor_(free)(state, input);
  THCIndexTensor_(free)(state, indices);
}

void THNN_(VolumetricMaxUnpooling_updateGradInput)(
           THCState *state,
           THCTensor *input,
           THCTensor *gradOutput,
           THCTensor *gradInput,
           THCIndexTensor *indices,
           int outputTime, int outputWidth, int outputHeight,
           int dT, int dW, int dH,
           int padT, int padW, int padH)
{

  int batchSize;
  int inputSlices;
  int inputTime;
  int inputHeight;
  int inputWidth;

  THCUNN_assertSameGPU_generic(state, 4, input, indices, gradOutput, gradInput);

  if (THCTensor_(nDimension)(state, input) == 4) /* 4D */
  {
    batchSize = 1;
    inputSlices  = THCTensor_(size)(state, input, 0);
    inputTime   = THCTensor_(size)(state, input, 1);
    inputHeight = THCTensor_(size)(state, input, 2);
    inputWidth  = THCTensor_(size)(state, input, 3);
  }
  else
  {
    batchSize    = THCTensor_(size)(state, input, 0);
    inputSlices  = THCTensor_(size)(state, input, 1);
    inputTime   = THCTensor_(size)(state, input, 2);
    inputHeight = THCTensor_(size)(state, input, 3);
    inputWidth  = THCTensor_(size)(state, input, 4);
  }

  input = THCTensor_(newContiguous)(state, input);
  indices = THCIndexTensor_(newContiguous)(state, indices);
  gradOutput = THCTensor_(newContiguous)(state, gradOutput);
  THCTensor_(resizeAs)(state, gradInput, input);
  THCTensor_(zero)(state, gradInput);

  // Collapse batch and feature dimensions
  THCDeviceTensor<real, 4> cudaGradInput;
  THCDeviceTensor<real, 4> cudaGradOutput;
  THCDeviceTensor<THCIndex_t, 4> cudaIndices;

  if (THCTensor_(nDimension)(state, input) == 4)
  {
    cudaGradInput  = toDeviceTensor<real, 4>(state, gradInput);
    cudaGradOutput = toDeviceTensor<real, 4>(state, gradOutput);
    cudaIndices = toDeviceTensor<THCIndex_t, 4>(state, indices);
  }
  else
  {
    cudaGradInput =
      toDeviceTensor<real, 5>(state, gradInput).downcastOuter<4>();
    cudaGradOutput =
      toDeviceTensor<real, 5>(state, gradOutput).downcastOuter<4>();
    cudaIndices =
      toDeviceTensor<THCIndex_t, 5>(state, indices).downcastOuter<4>();
  }

  int totalZ = inputTime * inputSlices * batchSize;
  int offsetZ = 0;
  dim3 block(32, 8);

  while (totalZ > 0) {
    dim3 grid(THCCeilDiv(inputWidth, static_cast<int>(block.x)),
              THCCeilDiv(inputHeight, static_cast<int>(block.y)),
              totalZ > 65535 ? 65535 : totalZ);

    cuda_VolumetricMaxUnpooling_updateGradInput<<<grid, block,
      0, THCState_getCurrentStream(state)>>>(
                                             cudaGradOutput,
                                             cudaIndices,
                                             cudaGradInput,
                                             dT, dH, dW,
                                             padT, padH, padW, offsetZ);
    THCudaCheck(cudaGetLastError());
    totalZ -= 65535;
    offsetZ += 65535;
  }

  // cleanup
  THCTensor_(free)(state, input);
  THCTensor_(free)(state, gradOutput);
  THCIndexTensor_(free)(state, indices);
}

#endif
