# CSCI 5619 Final Project
> Brock Shamblin, shamb041@umn.edu

> Godot Version: 4.1.1

This project started with the starter code and environment from [Assignment 4](https://github.com/CSCI-5619-Fall-2023/Assignment-4)

## Submission Information

You should fill out this information before submitting your assignment. 

1. **Ready for Grading**. When your assignment is complete, you should change the line below to YES and then push to GitHub. This will signal to the TA that your assignment is ready to be graded. If the submission is completed after the due date, the timestamp of the commit will be used to determine how many late points will be applied.

   `YES`

2. **Third Party Assets**. List the name and source of any third party assets that you added, such as models, images, sounds, or any other content used that was not created by you.

   `NONE`

3. **Grading Instructions**. Please provide a brief description of your VR experience, identify the interaction techniques you implemented, and provide any usage instructions needed for the person grading your assignment.

    This project implements a redirected walking technique that allows for walking along a twisty virtual path in a confined physical space. Specifically, the space is assumed to be a concave polygon. At the time of implementation, the OpenXR API to get the guardian boundary of a room is unimplemented, so the world boundary is hard-coded to be an L-shaped room.

    The user is placed at the start of the path, facing the first target. The user will walk and hit each target along the path. Once the user hits the target or reaches a world boundary, the user will be prompted to spin around until they are facing the correct direction both virtually and physically. They will be physically aimed at a different point on the boundary that is the furthest away from them without crossing any other boundaries. They will be virtually aimed in the general direction of the target once again.

