// Copyright (c) 2017 Doyub Kim
//
// I am making my contributions/submissions to this project solely in my
// personal capacity and am not conveying any rights to any intellectual
// property of any third parties.


#include <jet/cuda_array1.h>
#include <jet/cuda_array_view1.h>

#include <gtest/gtest.h>

using namespace jet;
using namespace experimental;

TEST(CudaArray1, Constructors) {
    {
        CudaArray1<float> arr;
        EXPECT_EQ(0u, arr.size());
    }
    {
        CudaArray1<float> arr(9, 1.5f);
        EXPECT_EQ(9u, arr.size());
        for (size_t i = 0; i < 9; ++i) {
            EXPECT_FLOAT_EQ(1.5f, arr[i]);
        }
    }
}

TEST(CudaArray1, View) {
    CudaArray1<float> arr(15, 3.14f);
    CudaArrayView1<float> view = arr.view();
    EXPECT_EQ(15u, view.size());
    EXPECT_EQ(arr.data(), view.data());
    for (size_t i = 0; i < 15; ++i) {
        EXPECT_FLOAT_EQ(3.14f, view[i]);
    }
}
